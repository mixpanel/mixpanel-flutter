import 'dart:async' show Timer;
import 'dart:math' show Random;
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../models/configuration.dart';
import '../models/debug_overlay_colors.dart';
import '../models/masking_directive.dart';
import '../models/results.dart';
import '../models/session_event.dart' show TouchPosition;
import '../models/session.dart';
import 'background_task_manager.dart';
import 'event_recorder.dart';
import 'screenshot_capturer.dart';
import 'triggers/trigger_service.dart';
import 'upload/upload_service.dart';
import 'settings/settings_service.dart';
import 'session/session_manager.dart';
import 'session/idle_timeout_timer.dart';
import 'session/recording_limits.dart';
import 'widget_coordinator.dart';
import 'session_replay_sender.dart';
import 'logger.dart';

/// Internal coordinator for widget-level session replay operations
///
/// This class handles all internal widget callbacks and is NOT part of the public API.
/// Widgets use this coordinator to trigger captures, record interactions, etc.
class SessionReplayCoordinator implements WidgetCoordinator {
  final ScreenshotCapturer _screenshotCapturer;
  final EventRecorder _eventRecorder;
  final UploadService _uploadService;
  final SettingsService _settingsService;
  final SessionManager _sessionManager;
  final BackgroundTaskManager _backgroundTaskManager;
  final MixpanelLogger _logger;
  late final TriggerService _triggerService = TriggerService(
    logger: _logger,
    onTriggerFired: (percentage) {
      // Match native: explicitly log when a trigger matches but a session
      // is already in progress, so the "Trigger fired" log isn't followed
      // by a silent no-op inside startRecording.
      if (_recordingState != RecordingState.notRecording) {
        _logger.debug(
          'Trigger matched but recording already in progress, skipping start',
          tag: 'triggers',
        );
        return;
      }
      startRecording(sessionsPercent: percentage);
    },
  );

  RecordingState _recordingState = RecordingState.notRecording;
  bool _isAppInForeground = false;
  bool _isDisposed = false;

  /// Incremented when a background pause invalidates captures that started
  /// while recording was active.
  int _captureGeneration = 0;

  @override
  bool get capturesRenderedSurface =>
      _screenshotCapturer.capturesRenderedSurface;

  // Store the result of the settings check
  RemoteEnablementState _remoteEnablementState = RemoteEnablementState.pending;

  // Notifier for mask regions (for debug overlay)
  final ValueNotifier<List<MaskRegionInfo>> _maskRegions =
      ValueNotifier<List<MaskRegionInfo>>([]);

  // Store auto-record configuration for lifecycle events
  double _autoRecordSessionsPercent;

  // Remote settings mode
  final RemoteSettingsMode _remoteSettingsMode;

  // Debug options configuration (null = disabled)
  final DebugOptions? _debugOptions;

  // Reusable random instance for sampling decisions
  static final Random _random = Random();

  // -- Web idle timeout / session resume --

  /// Idle timeout timer (web only, null on native)
  IdleTimeoutTimer? _idleTimer;

  /// Max session duration (web only, null on native)
  Duration? _maxSessionDuration;

  /// Absolute expiry time for the current session's max duration
  DateTime? _maxSessionExpiry;

  /// Idle deadline carried over from a persisted session, so resuming keeps
  /// the remaining inactivity window rather than starting a fresh one.
  DateTime? _pendingResumeIdleExpiry;

  /// Fires at [_maxSessionExpiry].
  ///
  /// [_checkMaxSessionExpired] only runs on the capture and interaction paths,
  /// so a static page -- especially one with the idle timeout disabled --
  /// could otherwise stay registered past its maximum duration indefinitely.
  Timer? _maxSessionTimer;

  /// Wall-clock deadline mirroring [_idleTimer].
  ///
  /// The timer alone is not enough: a hidden tab throttles timers but still
  /// fires them, whereas bfcache and OS suspension freeze the page entirely,
  /// so wall-clock time passes without the timer advancing. Kept in step with
  /// the timer by [_restartIdleWindow] and checked on foreground.
  DateTime? _idleExpiry;

  /// A persisted web session waiting for the fresh remote enablement verdict.
  /// Keeping it staged prevents screenshots and interactions from being
  /// captured locally before the project has allowed recording this launch.
  Session? _pendingResumableSession;

  /// True when recording was stopped due to idle timeout (awaiting next interaction)
  bool _isIdledOut = false;

  /// Configured behavior when the app or page leaves the foreground.
  final ReplayBackgroundBehavior _backgroundBehavior;

  /// Wall-clock deadline for retaining a replay while backgrounded.
  DateTime? _backgroundPauseExpiry;

  /// Callback to persist idle expiry to IndexedDB (web only)
  final Future<void> Function(
    String sessionId,
    int idleExpiresMs,
    int maxExpiresMs,
  )?
  _persistIdleExpiry;

  /// Debounce: last time we persisted idle expiry to IndexedDB
  DateTime? _lastExpiryWriteTime;

  /// Debounce interval for expiry writes (avoid excessive IDB writes)
  static const _expiryWriteDebounce = Duration(seconds: 5);

  SessionReplayCoordinator({
    required ScreenshotCapturer screenshotCapturer,
    required EventRecorder eventRecorder,
    required UploadService uploadService,
    required SettingsService settingsService,
    required SessionManager sessionManager,
    required MixpanelLogger logger,
    required double autoRecordSessionsPercent,
    required RemoteSettingsMode remoteSettingsMode,
    required DebugOptions? debugOptions,
    BackgroundTaskManager? backgroundTaskManager,
    IdleTimeoutTimer? idleTimer,
    Duration? maxSessionDuration,
    required ReplayBackgroundBehavior backgroundBehavior,
    Future<void> Function(
      String sessionId,
      int idleExpiresMs,
      int maxExpiresMs,
    )?
    persistIdleExpiry,
  }) : _screenshotCapturer = screenshotCapturer,
       _eventRecorder = eventRecorder,
       _uploadService = uploadService,
       _settingsService = settingsService,
       _sessionManager = sessionManager,
       _backgroundTaskManager =
           backgroundTaskManager ?? BackgroundTaskManager(),
       _logger = logger,
       _autoRecordSessionsPercent = autoRecordSessionsPercent,
       _remoteSettingsMode = remoteSettingsMode,
       _debugOptions = debugOptions,
       _idleTimer = idleTimer,
       _maxSessionDuration = maxSessionDuration,
       _backgroundBehavior = backgroundBehavior,
       _persistIdleExpiry = persistIdleExpiry {
    // Note: We do NOT auto-start recording in constructor
    // Recording will be started by LifecycleObserver when it detects app is resumed
    if (autoRecordSessionsPercent > 0) {
      _logger.info(
        'Session replay auto-recording enabled. Sampling rate: $autoRecordSessionsPercent%',
      );
      _logger.info(
        'Recording will start when LifecycleObserver detects app is in foreground',
      );
    } else {
      _logger.info(
        'Session replay manual recording mode - call startRecording() to begin',
      );
    }
  }

  /// Current recording state
  @override
  RecordingState get recordingState => _recordingState;

  /// Whether app is currently in foreground (used by FrameMonitor to stop captures when backgrounded)
  @override
  bool get isAppInForeground => _isAppInForeground;

  /// Remote settings state (pending, enabled, or disabled)
  @override
  RemoteEnablementState get remoteEnablementState => _remoteEnablementState;

  /// Logger instance for this coordinator
  @override
  MixpanelLogger get logger => _logger;

  /// Debug options configuration (null = debug disabled)
  DebugOptions? get debugOptions => _debugOptions;

  /// Whether the SDK is allowed to evaluate tracked events against
  /// Event Triggers. Reflects the user-controlled toggle only — does
  /// not imply any triggers are actually configured or being evaluated.
  bool get isEventTriggersEnabled => _triggerService.isEnabled;

  /// Opt out of trigger evaluation. Matched events stop firing recording.
  /// No-op when no triggers are configured.
  void disableEventTriggers() => _triggerService.disable();

  /// Opt back in to trigger evaluation. Enabled by default at SDK init.
  /// Does not cause triggers to be evaluated unless remote settings has
  /// delivered any.
  void enableEventTriggers() => _triggerService.enable();

  /// Get the replay ID of the current recording session
  ///
  /// Returns the session ID when recording is active (initializing or recording),
  /// null otherwise.
  String? get replayId {
    if (_recordingState == RecordingState.initializing ||
        _recordingState == RecordingState.recording) {
      return _sessionManager.getCurrentSession().id;
    }
    return null;
  }

  /// Notifier for debug mask regions (for overlay visualization)
  @override
  ValueNotifier<List<MaskRegionInfo>> get maskRegionsNotifier => _maskRegions;

  /// Capture a screenshot from the given boundary
  ///
  /// This is called by FrameMonitor when its scheduler determines a capture should happen.
  /// Coordinates the capture process: gets JPG from recorder, passes to event recorder.
  @override
  Future<void> captureSnapshot(
    RenderRepaintBoundary boundary, {
    required Element boundaryElement,
  }) async {
    // Check if disposed first (prevents captures during shutdown)
    if (_isDisposed) {
      _logger.debug(
        'Coordinator disposed, skipping snapshot capture',
        tag: 'coordinator',
      );
      return;
    }

    if (_recordingState != RecordingState.recording) {
      _logger.debug(
        'Recording not active, skipping snapshot capture',
        tag: 'coordinator',
      );
      return;
    }

    // Check max session duration (web only)
    if (_checkMaxSessionExpired()) return;

    final captureGeneration = _captureGeneration;
    _logger.debug('Capturing snapshot', tag: 'coordinator');

    // Get JPG bytes from screenshot capturer
    final result = await _screenshotCapturer.capture(
      boundary,
      getCurrentSession: _sessionManager.getCurrentSession,
      getDistinctId: _eventRecorder.getDistinctId,
      boundaryElement: boundaryElement,
    );

    // A pause may have happened while the asynchronous image capture was in
    // flight, followed by a resume before it completed. Checking only the
    // current recording state would let that stale frame cross the pause
    // boundary, so use the generation captured when the work began.
    if (_captureGeneration != captureGeneration) {
      _logger.debug(
        'Discarding snapshot captured across a background pause',
        tag: 'coordinator',
      );
      return;
    }

    // Handle result using pattern matching
    switch (result) {
      case CaptureSuccess(
        :final data,
        :final width,
        :final height,
        :final timestamp,
        :final maskRegions,
        :final sessionId,
        :final distinctId,
        :final wireframes,
      ):
        // Update mask regions for debug overlay (only if overlay is enabled)
        // Diff check prevents feedback loop: overlay rebuild → new frame → capture → repeat
        // dispose() disposes this notifier, and writing to a disposed one asserts
        if (!_isDisposed &&
            _debugOptions?.overlayColors != null &&
            !listEquals(_maskRegions.value, maskRegions)) {
          _maskRegions.value = maskRegions;
        }

        // Pass JPG bytes to event recorder to save with the capture timestamp
        await _eventRecorder.recordSnapshot(
          imageData: data,
          width: width,
          height: height,
          timestamp: timestamp,
          sessionId: sessionId,
          distinctId: distinctId,
        );

        // Emit wireframe alongside the screenshot with the same timestamp
        // so downstream ordering by ID aligns wireframe → matching screenshot.
        // Null when wireframes are disabled or the emitter deduped this frame.
        if (wireframes != null) {
          await _eventRecorder.recordWireframe(
            payload: wireframes,
            timestamp: timestamp,
            sessionId: sessionId,
            distinctId: distinctId,
          );
        }

        // Reset idle timer and persist expiry (web only)
        _onActivity();
      case CaptureFailure(:final error, :final errorMessage):
        _logger.debug(
          'Capture failed: $error - $errorMessage',
          tag: 'coordinator',
        );
    }
  }

  /// Capture a gesture boundary with a specific type
  ///
  /// [interactionType] - The RRWeb interaction type (touchStart, touchEnd,
  /// touchCancel)
  /// [position] - The position where the interaction occurred
  /// [timestamp] - When the pointer event happened
  @override
  void captureInteraction(
    int interactionType,
    Offset position,
    DateTime timestamp,
  ) {
    if (!_canRecordTouch('interaction')) return;

    // Check max session duration (web only)
    if (_checkMaxSessionExpired()) return;

    _logger.debug(
      'recordInteraction called with type: $interactionType, position: $position',
      tag: 'coordinator',
    );
    _eventRecorder.recordInteraction(interactionType, position, timestamp);

    // Reset idle timer and persist expiry (web only)
    _onActivity();
  }

  /// Capture a batch of sampled drag positions
  ///
  /// [positions] - Sampled positions, oldest first
  /// [timestamp] - When the final position happened
  @override
  void captureTouchMove(List<TouchPosition> positions, DateTime timestamp) {
    if (!_canRecordTouch('touch move')) return;

    _logger.debug(
      'recordTouchMove called with ${positions.length} positions',
      tag: 'coordinator',
    );
    _eventRecorder.recordTouchMove(positions: positions, timestamp: timestamp);
  }

  /// Shared gate for the touch stream: never record while disposed or while
  /// recording is inactive.
  bool _canRecordTouch(String what) {
    // Check if disposed first (prevents captures during shutdown)
    if (_isDisposed) {
      _logger.debug(
        'Coordinator disposed, skipping $what capture',
        tag: 'coordinator',
      );
      return false;
    }

    if (_recordingState != RecordingState.recording) {
      _logger.debug(
        'Recording not active, skipping $what capture',
        tag: 'coordinator',
      );
      return false;
    }

    return true;
  }

  /// Flush queued events to server
  ///
  /// Triggers an immediate upload of queued events.
  ///
  /// Returns a [FlushResult] indicating the operation completed. Note that flush
  /// is a best-effort operation that may partially succeed.
  Future<FlushResult> flush() async {
    _logger.debug('flush called', tag: 'coordinator');
    return await _uploadService.flush();
  }

  /// Handle the app or page leaving the foreground.
  @override
  void onAppBackgrounded() {
    // Check if disposed first
    if (_isDisposed) {
      _logger.debug(
        'Coordinator disposed, skipping onAppBackgrounded',
        tag: 'coordinator',
      );
      return;
    }

    _logger.debug('onAppBackgrounded called', tag: 'coordinator');

    // Mark app as backgrounded (stops FrameMonitor captures)
    _isAppInForeground = false;

    _applyBackgroundBehaviorWithBackgroundTask();
  }

  /// Apply the configured background transition with background task
  /// protection for the final flush.
  ///
  /// On iOS, requests ~30 seconds of background execution time via
  /// UIApplication.beginBackgroundTask() so the flush can complete.
  /// On other platforms, the background task wrapper is a no-op.
  void _applyBackgroundBehaviorWithBackgroundTask() {
    _backgroundTaskManager.beginBackgroundTask();

    switch (_backgroundBehavior) {
      case ReplayBackgroundPauseBehavior(:final idleTimeout):
        _pauseForBackground(idleTimeout);
      case ReplayBackgroundStopBehavior():
        stopRecording(cancelPendingResume: false);
    }

    // Call flush() to join the in-progress flush via the completer,
    // then end the background task when it completes.
    _uploadService.flush().whenComplete(() {
      _backgroundTaskManager.endBackgroundTask();
    });
  }

  /// Handle app returning to foreground
  @override
  void onAppForegrounded() {
    // Check if disposed first
    if (_isDisposed) {
      _logger.debug(
        'Coordinator disposed, skipping onAppForegrounded',
        tag: 'coordinator',
      );
      return;
    }

    _logger.debug('onAppForegrounded called', tag: 'coordinator');

    // Mark app as foregrounded (allows FrameMonitor captures)
    _isAppInForeground = true;

    // A session carried across a hidden interval may have outlived either
    // window while away. Both are checked against wall clock: the idle timer
    // does not advance while the page is frozen in bfcache or suspended by
    // the OS, so it cannot be trusted on its own here. Either check stops
    // recording and marks the session idled out, so the branches below start
    // a fresh one.
    if ((_recordingState == RecordingState.recording ||
            _recordingState == RecordingState.paused) &&
        !_checkMaxSessionExpired() &&
        _idleWindowExpired()) {
      _logger.info(
        'Idle window elapsed while the page was away, ending session',
        tag: 'coordinator',
      );
      handleIdleTimeout();
    }

    switch (_remoteEnablementState) {
      case RemoteEnablementState.pending:
        _logger.debug(
          'First foreground - checking remote settings',
          tag: 'coordinator',
        );

        // Wait for settings before starting recording (matches Android/iOS)
        _settingsService
            .fetchRemoteSettings()
            .then((result) {
              _remoteEnablementState = result.isRecordingEnabled
                  ? RemoteEnablementState.enabled
                  : RemoteEnablementState.disabled;

              // The wireframe kill switch is an enablement switch, not remote
              // config, so it is honored in every remote settings mode and
              // regardless of whether recording itself is allowed. Forwarded
              // before the recording branch below because until the capturer
              // has the verdict it emits no wireframes at all.
              _applyWireframeVerdict(result);

              if (!result.isRecordingEnabled) {
                _logger.warning(
                  'Recording disabled by remote enablement check',
                  tag: 'coordinator',
                );
                stopRecording();
                return;
              }

              // Apply remote config based on mode (may disable in strict mode)
              _applyRemoteSettings(result);
              if (_remoteEnablementState == RemoteEnablementState.disabled) {
                return;
              }

              _logger.info(
                'Recording allowed by remote settings',
                tag: 'coordinator',
              );

              // A previous page may have persisted events without completing
              // its page-hide flush. Drain that backlog even when this page's
              // sampling decision does not start a new recording.
              _uploadService.flush().catchError((error) {
                _logger.warning(
                  'Failed to flush persisted replay backlog: $error',
                  tag: 'coordinator',
                );
                return FlushResult();
              });

              // Verify still in foreground after async settings check
              if (!_isAppInForeground) {
                _logger.debug(
                  'App backgrounded during settings check, not starting recording',
                  tag: 'coordinator',
                );
                return;
              }

              // Resume a persisted session only after the fresh enablement
              // verdict. Otherwise apply the normal auto-record decision.
              _resumeBackgroundPauseOrStart();
            })
            .catchError((error) {
              _logger.error(
                'Settings check failed: $error',
                null,
                null,
                'coordinator',
              );
              _remoteEnablementState = RemoteEnablementState.disabled;
            });

      case RemoteEnablementState.enabled:
        _resumeBackgroundPauseOrStart();

      case RemoteEnablementState.disabled:
        _logger.debug(
          'Recording remotely disabled, not starting recording',
          tag: 'coordinator',
        );
    }
  }

  void _resumeBackgroundPauseOrStart() {
    if (_recordingState == RecordingState.paused) {
      if (_backgroundPauseExpired()) {
        _logger.info(
          'Background pause idle timeout elapsed, ending session',
          tag: 'coordinator',
        );
        stopRecording(cancelPendingResume: false);
      } else {
        _resumeFromBackground();
        return;
      }
    }
    _startOrResumeRecording();
  }

  void _startOrResumeRecording() {
    final pendingSession = _pendingResumableSession;
    if (pendingSession != null) {
      _pendingResumableSession = null;
      final maxDuration = _maxSessionDuration;
      if (maxDuration != null &&
          !clock.now().isBefore(pendingSession.startTime.add(maxDuration))) {
        // A fresh remote maximum can be shorter than the limit used when the
        // web session was persisted. Start a new session instead of reviving it.
        _pendingResumeIdleExpiry = null;
        startRecording(sessionsPercent: _autoRecordSessionsPercent);
        return;
      }
      resumeSession(pendingSession);
      return;
    }
    startRecording(sessionsPercent: _autoRecordSessionsPercent);
  }

  /// Hands the server's wireframe verdict to the capturer.
  ///
  /// Always forwarded, including the `true` case: the capturer suppresses
  /// wireframes until it hears a verdict, so a frame captured by a manually
  /// started recording cannot ship a wireframe before `/settings` has answered.
  /// When the verdict is `false`, replay keeps recording and only the wireframe
  /// payload is dropped. No-op in effect when wireframes were never turned on
  /// locally — the capturer has no emitter either way.
  void _applyWireframeVerdict(RemoteSettingsResult result) {
    if (!result.isWireframeEnabled) {
      _logger.warning(
        'Wireframe capture is disabled via remote settings',
        tag: 'coordinator',
      );
    }
    _screenshotCapturer.applyRemoteWireframeVerdict(
      isEnabled: result.isWireframeEnabled,
    );
  }

  /// Applies remote settings to the coordinator based on [_remoteSettingsMode].
  ///
  /// In [RemoteSettingsMode.disabled] mode, remote SDK config values are ignored.
  ///
  /// In [RemoteSettingsMode.strict] mode, if the API call failed (isFromCache)
  /// or sdk_config is missing, recording is disabled entirely.
  ///
  /// In [RemoteSettingsMode.fallback] mode, remote/cached values are applied
  /// when available, otherwise local config is kept.
  void _applyRemoteSettings(RemoteSettingsResult result) {
    switch (_remoteSettingsMode) {
      case RemoteSettingsMode.disabled:
        _logger.info(
          'Remote settings mode is disabled, using local config',
          tag: 'coordinator',
        );
        return;

      case RemoteSettingsMode.strict:
        if (result.isFromCache || result.sdkConfig == null) {
          _logger.warning(
            'Strict mode: remote settings unavailable '
            '(fromCache=${result.isFromCache}, '
            'sdkConfig=${result.sdkConfig != null ? "present" : "null"}) '
            '- disabling recording',
            tag: 'coordinator',
          );
          _remoteEnablementState = RemoteEnablementState.disabled;
          stopRecording();
          return;
        }
        _applyRemoteConfigValues(result);

      case RemoteSettingsMode.fallback:
        _applyRemoteConfigValues(result);
    }
  }

  /// Applies remote config values to the coordinator.
  ///
  /// Only called from modes that opt in to remote config (strict + fresh,
  /// fallback). In [RemoteSettingsMode.disabled] and strict-with-cache-miss,
  /// this is skipped — so no remote config (including triggers) takes
  /// effect, while the remote enablement switch is still honored via the always-on
  /// `/settings` fetch.
  void _applyRemoteConfigValues(RemoteSettingsResult result) {
    _triggerService.updateTriggers(result.sdkConfig?.recordingEventTriggers);
    _applyRecordSessionsPercent(result);
    _applyWebRecordingDurations(result.sdkConfig);
  }

  void _applyWebRecordingDurations(SdkConfig? config) {
    // Native platform init does not supply a max session duration. Keep these
    // JS-specific settings confined to web, even when the server returns them
    // for another platform.
    if (_maxSessionDuration == null || config == null) return;

    final previousIdleTimeout = _idleTimer?.timeout;
    final previousIdleExpiry = _idleExpiry;
    var changed = false;

    if (config.recordMaxMs case final int maxMs) {
      _maxSessionDuration = capRecordingDuration(
        Duration(milliseconds: maxMs),
        name: 'record_max_ms',
        logger: _logger,
      );
      changed = true;
    }
    if (config.recordIdleTimeoutMs case final int idleMs) {
      _idleTimer?.dispose();
      _idleTimer = IdleTimeoutTimer(
        timeout: capRecordingDuration(
          Duration(milliseconds: idleMs),
          name: 'record_idle_timeout_ms',
          logger: _logger,
        ),
        onTimeout: handleIdleTimeout,
      );
      changed = true;
    }
    if (!changed || _recordingState == RecordingState.notRecording) return;

    // A manually started recording may already be active when the first
    // settings fetch finishes. Rebase its limits on the original session and
    // last activity rather than granting a new full lifetime.
    if (config.recordMaxMs != null) {
      _maxSessionExpiry = _sessionManager.getCurrentSession().startTime.add(
        _maxSessionDuration!,
      );
      if (_checkMaxSessionExpired()) return;
      _armMaxSessionTimer();
    }
    if (config.recordIdleTimeoutMs != null &&
        _recordingState != RecordingState.initializing) {
      final lastActivity =
          previousIdleExpiry != null && previousIdleTimeout != null
          ? previousIdleExpiry.subtract(previousIdleTimeout)
          : clock.now();
      final deadline = lastActivity.add(_idleTimer!.timeout);
      if (!clock.now().isBefore(deadline)) {
        handleIdleTimeout();
        return;
      }
      _restartIdleWindow(deadline: deadline);
    }
    _lastExpiryWriteTime = null;
    _persistExpiryDebounced();
  }

  void _applyRecordSessionsPercent(RemoteSettingsResult result) {
    final percent = result.sdkConfig?.recordSessionsPercent;
    if (percent == null) return;

    if (percent >= 0.0 && percent <= 100.0) {
      _logger.info(
        'Applying remote recordSessionsPercent: $percent',
        tag: 'coordinator',
      );
      _autoRecordSessionsPercent = percent;
    } else {
      _logger.warning(
        'Invalid remote recordSessionsPercent value: $percent. '
        'Must be between 0.0 and 100.0.',
        tag: 'coordinator',
      );
    }
  }

  /// Start recording session replay with optional sampling
  ///
  /// [sessionsPercent]: Percentage of sessions to record (0-100).
  /// Uses random sampling to determine if this session should be recorded.
  ///
  /// Called automatically on app foregrounding if autoStartRecording is enabled.
  /// Each foreground creates a new replay session with a fresh sampling decision.
  /// This matches the iOS and Android SDK behavior.
  void startRecording({double sessionsPercent = 100.0}) {
    // Check if disposed first
    if (_isDisposed) {
      _logger.debug(
        'Coordinator disposed, skipping startRecording',
        tag: 'coordinator',
      );
      return;
    }

    _logger.debug(
      'startRecording called (sampling: $sessionsPercent%)',
      tag: 'coordinator',
    );

    // Don't allow recording if remotely disabled
    if (_remoteEnablementState == RemoteEnablementState.disabled) {
      _logger.warning(
        'Cannot start recording - recording remotely disabled',
        tag: 'coordinator',
      );
      return;
    }

    // Only allow starting from notRecording state
    if (_recordingState != RecordingState.notRecording) {
      _logger.debug(
        'Recording already in progress (state: $_recordingState)',
        tag: 'coordinator',
      );
      return;
    }

    // Apply sampling logic (matches iOS/Android SDK behavior)
    if (sessionsPercent > 0 && _random.nextDouble() * 100 <= sessionsPercent) {
      _logger.info(
        'Session replay recording started! Sampling rate: $sessionsPercent%',
      );

      // A new session supersedes one still waiting for remote settings to
      // resume, so the settings verdict cannot swap it in mid-recording.
      // Matches mixpanel-js, which skips resuming while a recording is active.
      if (_pendingResumableSession case final pending?) {
        _logger.debug(
          'Discarding staged session ${pending.id} for a new recording',
          tag: 'coordinator',
        );
        _pendingResumableSession = null;
        _pendingResumeIdleExpiry = null;
        _expirePersistedSession(pending.id);
      }

      // Create a new session (matches iOS/Android behavior)
      // This generates a new session ID for each foreground
      final session = _sessionManager.startNewSession();
      _logger.debug('New session created: ${session.id}', tag: 'coordinator');

      // Wireframe dedup is per session, not per SDK lifetime. The emitter is built once
      // in initialize() and outlives a stop/start cycle, so without this the new
      // session's first frame is compared against the previous session's last one — and
      // a background/foreground onto an unchanged screen dedups it away, shipping an
      // opening screenshot with no mp_wireframe to describe it. Matches iOS and Android,
      // which reset at the same point.
      _screenshotCapturer.resetWireframeDedup();

      // Transition to initializing immediately to prevent double-starts
      _recordingState = RecordingState.initializing;

      // Set max session expiry (web only)
      final maxSessionDuration = _maxSessionDuration;
      if (maxSessionDuration != null) {
        _maxSessionExpiry = clock.now().add(maxSessionDuration);
        _armMaxSessionTimer();
      }

      // Register replay ID as super property with the main Mixpanel SDK
      SessionReplaySender.register({'\$mp_replay_id': session.id});

      // Record session start in storage via EventRecorder
      // Enable recording only after session metadata is persisted to prevent
      // race condition where events are captured before metadata exists
      final sessionId = session.id;
      _eventRecorder.recordSession(session).then((_) {
        // Only transition to recording if:
        // 1. We're still in the initializing state (settings check or
        //    stopRecording() may have set us to notRecording), AND
        // 2. This callback is for the current session (a stop/start cycle
        //    may have created a new session while we were persisting)
        if (_recordingState != RecordingState.initializing ||
            _sessionManager.getCurrentSession().id != sessionId) {
          _logger.debug(
            'Session metadata persisted but state changed to $_recordingState '
            'or session changed, not transitioning to recording',
            tag: 'coordinator',
          );
          // A stop that ran before the metadata existed had nothing to
          // expire. Expire it now so a reload cannot resume this session.
          if (_recordingState == RecordingState.notRecording ||
              _sessionManager.getCurrentSession().id != sessionId) {
            _expirePersistedSession(sessionId);
          }
          return;
        }
        _recordingState = RecordingState.recording;
        _uploadService.startAutoFlush();
        _restartIdleWindow();
        // Persist initial expiry to IndexedDB (web only, force write)
        _lastExpiryWriteTime = null;
        _persistExpiryDebounced();
        _logger.debug(
          'Session metadata persisted, recording enabled',
          tag: 'coordinator',
        );
      });
    } else {
      _logger.info(
        'Session replay recording not started due to sampling rate ($sessionsPercent%)',
      );
      // Stay in notRecording state - allows re-rolling on next startRecording() call
      // This matches iOS/Android SDK behavior
    }
  }

  /// Pause the current replay while the app or page is backgrounded.
  void _pauseForBackground(Duration idleTimeout) {
    if (_isDisposed) {
      _logger.debug(
        'Coordinator disposed, skipping background pause',
        tag: 'coordinator',
      );
      return;
    }

    if (_recordingState != RecordingState.initializing &&
        _recordingState != RecordingState.recording) {
      _logger.debug(
        'Recording is not active, skipping background pause',
        tag: 'coordinator',
      );
      return;
    }

    _logger.debug('Pausing recording for background', tag: 'coordinator');
    _captureGeneration++;
    _recordingState = RecordingState.paused;
    _backgroundPauseExpiry = clock.now().add(idleTimeout);

    // Preserve the latest web idle deadline before the page may be frozen or
    // discarded. Native platforms do not provide this callback.
    _lastExpiryWriteTime = null;
    _persistExpiryDebounced();

    if (_maskRegions.value.isNotEmpty) {
      _maskRegions.value = const <MaskRegionInfo>[];
    }

    _uploadService.stopAutoFlush();
    SessionReplaySender.unregister('\$mp_replay_id');
    _uploadService.flush().catchError((e) {
      _logger.error(
        'Failed to flush events on pause: $e',
        null,
        null,
        'coordinator',
      );
      return FlushResult();
    });

    _logger.debug('Recording paused', tag: 'coordinator');
  }

  /// Resume a paused replay with the same replay ID.
  void _resumeFromBackground() {
    if (_isDisposed) {
      _logger.debug(
        'Coordinator disposed, skipping foreground resume',
        tag: 'coordinator',
      );
      return;
    }

    if (_recordingState != RecordingState.paused) {
      _logger.debug(
        'Recording is not paused, skipping foreground resume',
        tag: 'coordinator',
      );
      return;
    }

    if (_remoteEnablementState == RemoteEnablementState.disabled) {
      _logger.warning(
        'Cannot resume recording - recording remotely disabled',
        tag: 'coordinator',
      );
      return;
    }

    // Web sessions still obey their idle and maximum-duration boundaries
    // while paused. Native platforms have neither deadline configured.
    if (_checkMaxSessionExpired()) return;
    if (_idleWindowExpired()) {
      handleIdleTimeout();
      return;
    }

    final session = _sessionManager.getCurrentSession();
    _logger.debug(
      'Resuming session replay recording: ${session.id}',
      tag: 'coordinator',
    );

    _screenshotCapturer.resetWireframeDedup();
    SessionReplaySender.register({'\$mp_replay_id': session.id});

    _recordingState = RecordingState.recording;
    _backgroundPauseExpiry = null;
    _uploadService.startAutoFlush();

    // If backgrounding interrupted initial session setup, the metadata callback
    // did not start the web idle window because the state was paused. Initialize
    // it now. Existing sessions retain their original idle deadline.
    if (_idleTimer != null && _idleExpiry == null) {
      _restartIdleWindow();
      _lastExpiryWriteTime = null;
      _persistExpiryDebounced();
    }

    _logger.debug('Recording resumed', tag: 'coordinator');
  }

  /// Stop recording session replay
  ///
  /// Stops recording and resets the sampling state. After calling this,
  /// you can call startRecording() again with a new sampling percentage.
  ///
  /// Called automatically on app backgrounding to end the current replay session.
  /// Also flushes pending events to ensure data is uploaded (matches iOS behavior).
  void stopRecording({bool cancelPendingResume = true}) {
    // Check if disposed first
    if (_isDisposed) {
      _logger.debug(
        'Coordinator disposed, skipping stopRecording',
        tag: 'coordinator',
      );
      return;
    }

    _logger.debug('stopRecording called', tag: 'coordinator');

    // A stopped replay must not come back on the next page load, so its
    // persisted deadlines are expired along with the in-memory ones below.
    if (_recordingState != RecordingState.notRecording) {
      _expirePersistedSession(_sessionManager.getCurrentSession().id);
    }
    if (cancelPendingResume) {
      if (_pendingResumableSession case final pending?) {
        _expirePersistedSession(pending.id);
      }
      _pendingResumableSession = null;
    }

    // Transition to notRecording state
    _recordingState = RecordingState.notRecording;

    // Clear debug overlay regions — no captures are happening, so the
    // previously-rendered mask outlines should disappear immediately.
    if (_maskRegions.value.isNotEmpty) {
      _maskRegions.value = const <MaskRegionInfo>[];
    }

    // Stop automatic uploads and idle timer
    _uploadService.stopAutoFlush();
    _idleTimer?.stop();
    _idleExpiry = null;
    _backgroundPauseExpiry = null;
    _maxSessionExpiry = null;
    _maxSessionTimer?.cancel();
    _maxSessionTimer = null;

    // Unregister replay ID from the main Mixpanel SDK
    SessionReplaySender.unregister('\$mp_replay_id');

    // Flush all pending events
    // This ensures events are uploaded when user explicitly stops or app backgrounds
    _uploadService.flush().catchError((e) {
      _logger.error(
        'Failed to flush events on stop: $e',
        null,
        null,
        'coordinator',
      );
      return FlushResult(); // Return FlushResult for error handler
    });

    _logger.debug('Recording stopped, state reset', tag: 'coordinator');
  }

  // -- Web idle timeout / session resume methods --

  /// Notify coordinator of user activity (even when not recording).
  ///
  /// Used on web to restart recording after an idle timeout.
  /// On native (or when no idle timeout is configured), this is a no-op.
  @override
  void onUserActivity() {
    if (_isIdledOut) {
      _logger.info(
        'User activity detected after idle timeout, starting new session',
        tag: 'coordinator',
      );
      _isIdledOut = false;
      startRecording(sessionsPercent: _autoRecordSessionsPercent);
    }
  }

  /// Handle idle timeout expiry.
  ///
  /// Called by [IdleTimeoutTimer] when the idle timeout fires.
  /// Stops recording and sets [_isIdledOut] so the next user interaction
  /// triggers a new session via [onUserActivity].
  void handleIdleTimeout() {
    if (_isDisposed || _recordingState == RecordingState.notRecording) return;

    _logger.info('Idle timeout fired, stopping recording', tag: 'coordinator');
    stopRecording();
    _isIdledOut = true;
  }

  /// Resume a previously persisted session (web only).
  ///
  /// Called during initialization when a valid non-expired session is found
  /// in IndexedDB. Restores the session without creating a new one or
  /// re-rolling sampling.
  void resumeSession(Session session) {
    if (_isDisposed) return;

    _logger.info('Resuming session: ${session.id}', tag: 'coordinator');

    _pendingResumableSession = null;
    final resumeIdleExpiry = _pendingResumeIdleExpiry;
    _pendingResumeIdleExpiry = null;

    _sessionManager.resumeSession(session);

    // Set max session expiry based on original start time
    final maxSessionDuration = _maxSessionDuration;
    if (maxSessionDuration != null) {
      _maxSessionExpiry = session.startTime.add(maxSessionDuration);
      _armMaxSessionTimer();
    }

    // Register replay ID as super property
    SessionReplaySender.register({'\$mp_replay_id': session.id});

    _recordingState = RecordingState.recording;
    _uploadService.startAutoFlush();
    // Keep the stored deadline: re-arming for the full timeout would give a
    // reload near the end of the window another complete one.
    final timer = _idleTimer;
    final maximumIdleDeadline = timer == null
        ? null
        : clock.now().add(timer.timeout);
    final idleDeadline =
        resumeIdleExpiry != null &&
            maximumIdleDeadline != null &&
            resumeIdleExpiry.isBefore(maximumIdleDeadline)
        ? resumeIdleExpiry
        : maximumIdleDeadline;
    _restartIdleWindow(deadline: idleDeadline);
  }

  /// Stage a persisted web session until remote recording enablement has been
  /// checked for this page load.
  void prepareSessionResume(Session session, {DateTime? idleExpiry}) {
    if (_isDisposed) return;
    _pendingResumableSession = session;
    _pendingResumeIdleExpiry = idleExpiry;
    _logger.info(
      'Session ${session.id} is eligible for resume; waiting for remote settings',
      tag: 'coordinator',
    );
  }

  /// Reset idle timer and persist expiry (debounced). Called on every
  /// successful capture or interaction.
  void _onActivity() {
    _restartIdleWindow();
    _persistExpiryDebounced();
  }

  /// Start or restart the idle window, keeping the timer and its wall-clock
  /// twin in step.
  void _restartIdleWindow({DateTime? deadline}) {
    final timer = _idleTimer;
    if (timer == null) return;
    final now = clock.now();
    final target = deadline ?? now.add(timer.timeout);
    _idleExpiry = target;
    final remaining = target.difference(now);
    timer.resetWith(remaining.isNegative ? Duration.zero : remaining);
  }

  /// Whether a max-duration timer is currently armed. Test seam.
  @visibleForTesting
  bool get hasMaxSessionTimerForTest => _maxSessionTimer?.isActive ?? false;

  /// (Re)arm the max-duration timer from [_maxSessionExpiry].
  void _armMaxSessionTimer() {
    _maxSessionTimer?.cancel();
    final expiry = _maxSessionExpiry;
    if (expiry == null) return;
    final remaining = expiry.difference(clock.now());
    if (remaining.isNegative || remaining == Duration.zero) {
      _checkMaxSessionExpired();
      return;
    }
    _maxSessionTimer = Timer(remaining, () {
      if (_isDisposed) return;
      if (_recordingState != RecordingState.recording) return;
      _logger.info(
        'Max session duration reached, ending session',
        tag: 'coordinator',
      );
      _checkMaxSessionExpired();
    });
  }

  /// Whether wall-clock time has passed the idle deadline.
  ///
  /// Catches the intervals [_idleTimer] cannot see, where the page was frozen
  /// rather than merely hidden.
  bool _idleWindowExpired() {
    final expiry = _idleExpiry;
    return expiry != null && clock.now().isAfter(expiry);
  }

  bool _backgroundPauseExpired() {
    final expiry = _backgroundPauseExpiry;
    return expiry != null && !clock.now().isBefore(expiry);
  }

  /// Check if max session duration has been exceeded.
  /// Returns true if expired (and triggers idle-out flow).
  bool _checkMaxSessionExpired() {
    final expiry = _maxSessionExpiry;
    if (expiry == null) return false;
    if (!clock.now().isBefore(expiry)) {
      _logger.info(
        'Max session duration exceeded, stopping recording',
        tag: 'coordinator',
      );
      stopRecording();
      _isIdledOut = true;
      return true;
    }
    return false;
  }

  /// Mark a persisted session as expired so a page reload cannot resume it.
  ///
  /// Not debounced: a stop must reach storage even if an activity write just
  /// happened. IndexedDB runs readwrite transactions on the same store in
  /// creation order, so an earlier in-flight activity write cannot land after
  /// this one and revive the session.
  void _expirePersistedSession(String sessionId) {
    final persist = _persistIdleExpiry;
    if (persist == null) return;

    _lastExpiryWriteTime = null;
    final expiredMs = clock.now().millisecondsSinceEpoch - 1;
    persist(sessionId, expiredMs, expiredMs).catchError((e) {
      _logger.error(
        'Failed to expire persisted session: $e',
        null,
        null,
        'coordinator',
      );
    });
  }

  /// Persist idle expiry to IndexedDB (debounced to avoid excessive writes).
  void _persistExpiryDebounced() {
    final timer = _idleTimer;
    if (_persistIdleExpiry == null ||
        timer == null ||
        _maxSessionExpiry == null) {
      return;
    }

    final now = clock.now();
    if (_lastExpiryWriteTime != null &&
        now.difference(_lastExpiryWriteTime!) < _expiryWriteDebounce) {
      return;
    }

    _lastExpiryWriteTime = now;
    final sessionId = _sessionManager.getCurrentSession().id;
    final idleExpiresMs =
        (_idleExpiry ?? now.add(timer.timeout)).millisecondsSinceEpoch;

    _persistIdleExpiry(
      sessionId,
      idleExpiresMs,
      _maxSessionExpiry!.millisecondsSinceEpoch,
    ).catchError((e) {
      _logger.error(
        'Failed to persist idle expiry: $e',
        null,
        null,
        'coordinator',
      );
    });
  }

  /// Dispose resources
  ///
  /// Stops all captures, flushes pending events, then closes connections.
  ///
  /// Order is critical:
  /// 1. Set disposed flag (prevents new events from entering queue)
  /// 2. Flush pending events (upload everything currently queued)
  /// 3. Dispose services (close database, network, timers)
  Future<void> dispose() async {
    _logger.debug('dispose called', tag: 'coordinator');

    // STEP 1: Stop all captures (prevents race condition with flush)
    _isDisposed = true;
    _recordingState = RecordingState.notRecording;
    _pendingResumableSession = null;
    _logger.debug(
      'Marked as disposed - no more captures will be accepted',
      tag: 'coordinator',
    );

    // STEP 2: Flush any pending events before cleanup
    await flush();

    // STEP 3: Dispose services (stops timers, closes database)
    await _triggerService.dispose();
    _uploadService.dispose();
    _settingsService.dispose();
    _maxSessionTimer?.cancel();
    _idleTimer?.dispose();
    await _eventRecorder.dispose(); // Closes database connection
    _maskRegions.dispose();
    await _screenshotCapturer.dispose(); // Releases native cached resources

    _logger.debug('Coordinator disposed', tag: 'coordinator');
  }
}

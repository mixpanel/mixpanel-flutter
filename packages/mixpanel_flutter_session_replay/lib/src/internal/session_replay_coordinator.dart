import 'dart:math' show Random;
import 'package:flutter/foundation.dart'
    show ValueListenable, listEquals, visibleForTesting;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../models/configuration.dart';
import '../models/debug_overlay_colors.dart';
import '../models/masking_directive.dart';
import '../models/results.dart';
import '../models/session_event.dart' show TouchPosition;
import '../models/session.dart';
import 'background_task_manager.dart';
import 'capture/capture_invalidation.dart';
import 'debug_mask_overlay.dart';
import 'event_recorder.dart';
import 'screenshot_capturer.dart';
import 'triggers/trigger_service.dart';
import 'upload/upload_service.dart';
import 'settings/settings_service.dart';
import 'session/session_manager.dart';
import 'session/session_lifetime.dart';
import 'session/session_persistence.dart';
import 'session/replay_lifecycle_policy.dart';
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

  /// What a pause or stop means for captures already in flight.
  final CaptureInvalidation _captureInvalidation = CaptureInvalidation();

  final DebugMaskOverlayFactory _debugMaskOverlayFactory;

  @override
  DebugMaskOverlay createDebugMaskOverlay({
    required ValueListenable<List<MaskRegionInfo>> regions,
    required DebugOverlayColors colors,
    required RenderBox? Function() boundary,
  }) => _debugMaskOverlayFactory(
    regions: regions,
    colors: colors,
    boundary: boundary,
  );

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

  late final SessionLifetime _lifetime;

  /// True when recording was stopped due to idle timeout (awaiting next interaction)
  bool _isIdledOut = false;

  /// How the replay responds to leaving and re-entering the foreground.
  final ReplayLifecyclePolicy _lifecyclePolicy;

  /// Whether a foreground has applied the auto-record decision yet. Under a
  /// policy that does not resample, later foregrounds leave it as it is.
  bool _hasAppliedAutoRecord = false;

  /// Stores deadlines and offers a replay a previous page load left
  /// recording. A no-op on native platforms.
  final SessionPersistence _persistence;

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
    RecordingDurationLimits? durationLimits,
    required ReplayLifecyclePolicy lifecyclePolicy,
    DebugMaskOverlayFactory debugMaskOverlayFactory =
        InTreeDebugMaskOverlay.new,
    SessionPersistence? sessionPersistence,
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
       _lifecyclePolicy = lifecyclePolicy,
       _debugMaskOverlayFactory = debugMaskOverlayFactory,
       _persistence = sessionPersistence ?? SessionPersistence.none() {
    _lifetime = SessionLifetime(
      limits: durationLimits,
      onIdleExpired: handleIdleTimeout,
      onMaximumExpired: () => _endIfExpired(includeIdle: false),
    );
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

  @override
  bool get followsUpFramesDuringCapture =>
      _screenshotCapturer.followsUpFramesDuringCapture;

  @override
  bool get leavesForegroundWhenInactive =>
      _lifecyclePolicy.leavesForegroundWhenInactive;

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
    void Function()? onRenderTreeRead,
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

    // A capture is not activity, so only the maximum is checked here; the
    // idle timer is authoritative while the page is live.
    if (_endIfExpired(includeIdle: false)) return;

    final ticket = _captureInvalidation.begin();
    _logger.debug('Capturing snapshot', tag: 'coordinator');

    // Get JPG bytes from screenshot capturer. The capturer polls the probe
    // after each of its awaits so a stop or pause during the browser
    // presentation wait aborts before any pixels are acquired.
    final result = await _screenshotCapturer.capture(
      boundary,
      getCurrentSession: _sessionManager.getCurrentSession,
      getDistinctId: _eventRecorder.getDistinctId,
      boundaryElement: boundaryElement,
      isCancelled: () => _captureInvalidation.isCancelled(ticket),
      onRenderTreeRead: onRenderTreeRead,
    );

    // A pause may have happened while the asynchronous image capture was in
    // flight, followed by a resume before it completed. Checking only the
    // current recording state would let that stale frame cross the pause
    // boundary, so ask about the ticket taken when the work began.
    if (_captureInvalidation.discardsAcquired(ticket)) {
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
        // The frame is accepted: only now may its wireframe become the dedup
        // baseline, so a discarded frame cannot suppress the next one.
        _screenshotCapturer.commitWireframeDedup();

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
        // A capture is not user activity: like mixpanel-js, only input keeps
        // the idle window open, so a screen that repaints on its own still
        // idles out.
        if (wireframes != null) {
          await _eventRecorder.recordWireframe(
            payload: wireframes,
            timestamp: timestamp,
            sessionId: sessionId,
            distinctId: distinctId,
          );
        }
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

    // A drag is user input and keeps the idle window open (web only).
    _onActivity();
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

    // Input extends the idle window, so only the maximum can end the replay
    // here.
    return !_endIfExpired(includeIdle: false);
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

    switch (_lifecyclePolicy) {
      case PauseOnBackground(:final idleTimeout):
        _pauseForBackground(idleTimeout);
      case StopOnBackground():
        stopRecording(cancelPendingResume: false);
      case RecordThroughBackground():
        // The replay keeps recording while the page is hidden, and its idle
        // and maximum deadlines keep running. The page may be frozen or
        // discarded from here, so store the latest deadlines for a reload.
        if (_recordingState == RecordingState.recording) _writeDeadlinesNow();
    }

    // Call flush() to join the in-progress flush via the completer,
    // then end the background task when it completes. The error handler keeps
    // a storage failure from surfacing as an unhandled asynchronous error.
    _uploadService
        .flush()
        .catchError((Object e) {
          _logger.error(
            'Failed to flush events on background: $e',
            null,
            null,
            'coordinator',
          );
          return FlushResult();
        })
        .whenComplete(() {
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
    // window while away. The idle timer does not advance while the page is
    // frozen in bfcache or suspended by the OS, so it cannot be trusted on its
    // own here. An expired session is marked idled out, so the branches below
    // start a fresh one.
    if (_recordingState == RecordingState.recording ||
        _recordingState == RecordingState.paused) {
      _endIfExpired();
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
              // The fetch can outlive the coordinator (re-initialization
              // disposes it), and every step below uses disposed services.
              if (_isDisposed) return;
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
    final isFirstApplication = !_hasAppliedAutoRecord;
    _hasAppliedAutoRecord = true;

    // A replay that kept recording while hidden (web) has nothing to resume.
    if (_recordingState == RecordingState.initializing ||
        _recordingState == RecordingState.recording) {
      return;
    }
    if (_recordingState == RecordingState.paused) {
      if (_lifetime.isBackgroundExpired) {
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
    if (!isFirstApplication && !_lifecyclePolicy.resamplesOnForeground) {
      // As in mixpanel-js, auto-record was decided when the page loaded. A
      // replay that ended since then restarts on user activity instead.
      _logger.debug(
        'Auto-record already applied, foreground does not resample',
        tag: 'coordinator',
      );
      return;
    }
    _startOrResumeRecording();
  }

  void _startOrResumeRecording() {
    final pending = _persistence.takeResumable();
    if (pending != null) {
      if (!pending.isExpired(_lifetime.maximumDuration)) {
        resumeSession(pending.session, idleExpiry: pending.idleExpiry);
        return;
      }
      _persistence.expire(pending.session.id);
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
    // Native sessions have no activity/maximum duration limits.
    if (!_lifetime.hasLimits || config == null) return;
    if (config.recordMaxMs == null && config.recordIdleTimeoutMs == null) {
      return;
    }
    final active = _recordingState != RecordingState.notRecording;
    _lifetime.updateLimits(
      maximumDuration: config.recordMaxMs == null
          ? null
          : capRecordingDuration(
              Duration(milliseconds: config.recordMaxMs!),
              name: 'record_max_ms',
              logger: _logger,
            ),
      idleTimeout: config.recordIdleTimeoutMs == null
          ? null
          : capRecordingDuration(
              Duration(milliseconds: config.recordIdleTimeoutMs!),
              name: 'record_idle_timeout_ms',
              logger: _logger,
            ),
      activeSessionStart: active
          ? _sessionManager.getCurrentSession().startTime
          : null,
      initializing: _recordingState == RecordingState.initializing,
    );
    if (!active || _endIfExpired()) return;
    _writeDeadlinesNow();
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
  /// Whether each foreground applies a fresh sampling decision is up to the
  /// [ReplayLifecyclePolicy]: on native it does, matching the iOS and Android
  /// SDKs; on web it is decided once per page load, matching mixpanel-js.
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

    // A start attempt supersedes any earlier idle-triggered restart intent.
    _isIdledOut = false;

    // Apply sampling logic (matches iOS/Android SDK behavior)
    if (sessionsPercent > 0 && _random.nextDouble() * 100 <= sessionsPercent) {
      _logger.info(
        'Session replay recording started! Sampling rate: $sessionsPercent%',
      );

      // A new session supersedes one still waiting for remote settings to
      // resume, so the settings verdict cannot swap it in mid-recording.
      // Matches mixpanel-js, which skips resuming while a recording is active.
      if (_persistence.discardResumable() case final discarded?) {
        _logger.debug(
          'Discarding staged session ${discarded.session.id} for a new recording',
          tag: 'coordinator',
        );
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

      _lifetime.begin(session.startTime);

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
            _persistence.expire(sessionId);
          } else {
            // Still this session, now paused or already resumed to recording.
            // Every deadline write so far found no record to update, so land
            // the first one now rather than after the activity debounce.
            _writeDeadlinesNow();
          }
          return;
        }
        // Persistence can complete after a timer deadline. Recheck at the
        // transition instead of relying on timer callback ordering.
        if (_endIfExpired()) return;
        _recordingState = RecordingState.recording;
        _uploadService.startAutoFlush();
        _lifetime.recordActivity();
        // Persist initial expiry to IndexedDB (web only, force write)
        _writeDeadlinesNow();
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

  /// Pause the current replay while the app is backgrounded, under
  /// [PauseOnBackground]. Web never pauses: it records through a hidden page.
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
    _captureInvalidation.notePause();
    _recordingState = RecordingState.paused;
    _lifetime.pause(idleTimeout);

    // Stores the paused replay's deadlines. A no-op with native persistence,
    // kept so pausing stays correct for any persistence it is given.
    _writeDeadlinesNow();

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

    // A replay with duration limits still obeys them while paused. Native
    // replays have none, so this only matters if limits are configured.
    if (_endIfExpired()) return;

    final session = _sessionManager.getCurrentSession();
    _logger.debug(
      'Resuming session replay recording: ${session.id}',
      tag: 'coordinator',
    );

    _screenshotCapturer.resetWireframeDedup();
    SessionReplaySender.register({'\$mp_replay_id': session.id});

    _recordingState = RecordingState.recording;
    _lifetime.resumeBackground();
    _uploadService.startAutoFlush();

    // If backgrounding interrupted initial session setup, the metadata callback
    // did not start the idle window because the state was paused. Start it now.
    // Existing sessions retain their original idle deadline. Without an idle
    // timeout, as on native, there is no window to start.
    if (_lifetime.needsIdleWindow) {
      _lifetime.recordActivity();
    }
    // Store the resumed replay's deadlines even without fresh activity. A
    // no-op with native persistence.
    _writeDeadlinesNow();

    _logger.debug('Recording resumed', tag: 'coordinator');
  }

  /// Stop recording session replay
  ///
  /// Stops recording and resets the sampling state. After calling this,
  /// you can call startRecording() again with a new sampling percentage.
  ///
  /// Called automatically on app backgrounding to end the current replay session.
  /// Also flushes pending events to ensure data is uploaded (matches iOS behavior).
  void stopRecording({bool cancelPendingResume = true}) =>
      _stop(_StopReason.requested, cancelPendingResume: cancelPendingResume);

  void _stop(_StopReason reason, {bool cancelPendingResume = true}) {
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
      _persistence.expire(_sessionManager.getCurrentSession().id);
    }
    if (cancelPendingResume) _persistence.discardResumable();

    // Transition to notRecording state. A frame still waiting to acquire
    // pixels must not do so now; one already acquired stays with its replay.
    _captureInvalidation.noteStop();
    _recordingState = RecordingState.notRecording;
    _isIdledOut = reason.restartsOnActivity;

    // Clear debug overlay regions — no captures are happening, so the
    // previously-rendered mask outlines should disappear immediately.
    if (_maskRegions.value.isNotEmpty) {
      _maskRegions.value = const <MaskRegionInfo>[];
    }

    // Stop automatic uploads and idle timer
    _uploadService.stopAutoFlush();
    _lifetime.stop();

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
      // The replay that ended already passed sampling, or was started
      // explicitly. As in mixpanel-js, its successor is not sampled again.
      startRecording();
      return;
    }
    // Keyboard, wheel, and trackpad input reach the idle window only here;
    // pointer presses already refresh it through captureInteraction. Without
    // this, a session whose captures are being rejected (for example by
    // continuously moving masks) could idle out under active use.
    if (_recordingState == RecordingState.recording) {
      _onActivity();
    }
  }

  /// Handle idle timeout expiry.
  ///
  /// Called by [IdleTimeoutTimer] when the idle timeout fires. Stops
  /// recording so the next user interaction starts a new session via
  /// [onUserActivity].
  void handleIdleTimeout() {
    if (_isDisposed || _recordingState == RecordingState.notRecording) return;

    _logger.info('Idle timeout fired, stopping recording', tag: 'coordinator');
    _stop(_StopReason.idle);
  }

  /// Resume a previously persisted session (web only).
  ///
  /// Called during initialization when a valid non-expired session is found
  /// in IndexedDB. Restores the session without creating a new one or
  /// re-rolling sampling.
  void resumeSession(Session session, {DateTime? idleExpiry}) {
    if (_isDisposed) return;

    _logger.info('Resuming session: ${session.id}', tag: 'coordinator');

    _lifetime.resumeBackground();
    _isIdledOut = false;
    _sessionManager.resumeSession(session);
    _lifetime.begin(session.startTime);
    if (_endIfExpired()) return;

    // Register replay ID as super property
    SessionReplaySender.register({'\$mp_replay_id': session.id});

    _recordingState = RecordingState.recording;
    _uploadService.startAutoFlush();
    _lifetime.restoreIdleWindow(idleExpiry);
    _writeDeadlinesNow();
  }

  /// Reset idle timer and persist expiry (debounced). Called on every
  /// successful capture or interaction.
  void _onActivity() {
    _lifetime.recordActivity();
    _persistence.recordActivity(
      _sessionManager.getCurrentSession().id,
      _lifetime,
    );
  }

  /// Stores the current replay's deadlines, bypassing the activity debounce.
  void _writeDeadlinesNow() =>
      _persistence.writeNow(_sessionManager.getCurrentSession().id, _lifetime);

  @visibleForTesting
  bool get hasMaxSessionTimerForTest => _lifetime.hasMaximumTimer;

  /// Ends the replay if one of its deadlines has passed by wall clock, and
  /// returns whether it did.
  ///
  /// Checked at transitions as well as by the timers, since browser
  /// suspension can delay timer callbacks. An ended replay restarts on the
  /// next user activity. [includeIdle] false checks only the maximum.
  bool _endIfExpired({bool includeIdle = true}) {
    if (_isDisposed) return false;
    switch (_lifetime.expiredDeadline(includeIdle: includeIdle)) {
      case null:
        return false;
      case ExpiredDeadline.maximum:
        _logger.info(
          'Max session duration exceeded, stopping recording',
          tag: 'coordinator',
        );
        _stop(_StopReason.maximumDuration);
      case ExpiredDeadline.idle:
        _logger.info(
          'Idle window elapsed, stopping recording',
          tag: 'coordinator',
        );
        _stop(_StopReason.idle);
    }
    return true;
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
    // On web the super property lives for the whole page, so a replay ID
    // left registered would tag every later event with a dead replay.
    if (_recordingState != RecordingState.notRecording) {
      SessionReplaySender.unregister('\$mp_replay_id');
    }
    _recordingState = RecordingState.notRecording;
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
    _lifetime.dispose();
    await _eventRecorder.dispose(); // Closes database connection
    _maskRegions.dispose();
    await _screenshotCapturer.dispose(); // Releases native cached resources

    _logger.debug('Coordinator disposed', tag: 'coordinator');
  }
}

/// Why a replay stopped.
enum _StopReason {
  /// Stopped by the app, remote settings, or leaving the foreground.
  requested(restartsOnActivity: false),

  /// The idle window elapsed.
  idle(restartsOnActivity: true),

  /// The maximum session duration elapsed.
  maximumDuration(restartsOnActivity: true);

  const _StopReason({required this.restartsOnActivity});

  /// Whether the next user activity starts a new replay.
  final bool restartsOnActivity;
}

import 'dart:math' show Random;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../models/configuration.dart';
import '../models/debug_overlay_colors.dart';
import '../models/masking_directive.dart';
import '../models/results.dart';
import 'background_task_manager.dart';
import 'event_recorder.dart';
import 'screenshot_capturer.dart';
import 'triggers/trigger_service.dart';
import 'upload/upload_service.dart';
import 'settings/settings_service.dart';
import 'session/session_manager.dart';
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
       _debugOptions = debugOptions {
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
  Future<void> captureSnapshot(RenderRepaintBoundary boundary) async {
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

    _logger.debug('Capturing snapshot', tag: 'coordinator');

    // Get JPG bytes from screenshot capturer
    final result = await _screenshotCapturer.capture(boundary);

    // Handle result using pattern matching
    switch (result) {
      case CaptureSuccess(
        :final data,
        :final width,
        :final height,
        :final timestamp,
        :final maskRegions,
      ):
        // Update mask regions for debug overlay (only if overlay is enabled)
        // Diff check prevents feedback loop: overlay rebuild → new frame → capture → repeat
        if (_debugOptions?.overlayColors != null &&
            !listEquals(_maskRegions.value, maskRegions)) {
          _maskRegions.value = maskRegions;
        }

        // Pass JPG bytes to event recorder to save with the capture timestamp
        await _eventRecorder.recordSnapshot(
          imageData: data,
          width: width,
          height: height,
          timestamp: timestamp,
        );
      case CaptureFailure(:final error, :final errorMessage):
        _logger.debug(
          'Capture failed: $error - $errorMessage',
          tag: 'coordinator',
        );
    }
  }

  /// Capture an interaction event with a specific type
  ///
  /// [interactionType] - The RRWeb interaction type (e.g., touchStart, touchEnd, click)
  /// [position] - The position where the interaction occurred
  @override
  void captureInteraction(int interactionType, Offset position) {
    // Check if disposed first (prevents captures during shutdown)
    if (_isDisposed) {
      _logger.debug(
        'Coordinator disposed, skipping interaction capture',
        tag: 'coordinator',
      );
      return;
    }

    if (_recordingState != RecordingState.recording) {
      _logger.debug(
        'Recording not active, skipping interaction capture',
        tag: 'coordinator',
      );
      return;
    }

    _logger.debug(
      'recordInteraction called with type: $interactionType, position: $position',
      tag: 'coordinator',
    );
    _eventRecorder.recordInteraction(interactionType, position);
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

  /// Handle app going to background
  /// Stops recording and flushes all pending events
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

    // Stop recording and flush with background task protection (iOS)
    // This requests extended execution time so the flush HTTP request
    // completes before the OS suspends the process.
    _stopRecordingWithBackgroundTask();
  }

  /// Stop recording with background task protection for flush.
  ///
  /// On iOS, requests ~30 seconds of background execution time via
  /// UIApplication.beginBackgroundTask() so the flush can complete.
  /// On other platforms, this is a no-op wrapper around stopRecording().
  void _stopRecordingWithBackgroundTask() {
    // Request background time (fire-and-forget — don't delay stopRecording)
    _backgroundTaskManager.beginBackgroundTask();

    // stopRecording() must execute synchronously (state transitions immediately).
    // It triggers a fire-and-forget flush internally.
    stopRecording();

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

              // Verify still in foreground after async settings check
              if (!_isAppInForeground) {
                _logger.debug(
                  'App backgrounded during settings check, not starting recording',
                  tag: 'coordinator',
                );
                return;
              }

              // Auto-start recording after settings are resolved
              startRecording(sessionsPercent: _autoRecordSessionsPercent);
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
        startRecording(sessionsPercent: _autoRecordSessionsPercent);

      case RemoteEnablementState.disabled:
        _logger.debug(
          'Recording remotely disabled, not starting recording',
          tag: 'coordinator',
        );
    }
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

      // Create a new session (matches iOS/Android behavior)
      // This generates a new session ID for each foreground
      final session = _sessionManager.startNewSession();
      _logger.debug('New session created: ${session.id}', tag: 'coordinator');

      // Transition to initializing immediately to prevent double-starts
      _recordingState = RecordingState.initializing;

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
          return;
        }
        _recordingState = RecordingState.recording;
        _uploadService.startAutoFlush();
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

  /// Stop recording session replay
  ///
  /// Stops recording and resets the sampling state. After calling this,
  /// you can call startRecording() again with a new sampling percentage.
  ///
  /// Called automatically on app backgrounding to end the current replay session.
  /// Also flushes pending events to ensure data is uploaded (matches iOS behavior).
  void stopRecording() {
    // Check if disposed first
    if (_isDisposed) {
      _logger.debug(
        'Coordinator disposed, skipping stopRecording',
        tag: 'coordinator',
      );
      return;
    }

    _logger.debug('stopRecording called', tag: 'coordinator');

    // Transition to notRecording state
    _recordingState = RecordingState.notRecording;

    // Clear debug overlay regions — no captures are happening, so the
    // previously-rendered mask outlines should disappear immediately.
    if (_maskRegions.value.isNotEmpty) {
      _maskRegions.value = const <MaskRegionInfo>[];
    }

    // Stop automatic uploads
    _uploadService.stopAutoFlush();

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
    await _eventRecorder.dispose(); // Closes database connection
    _maskRegions.dispose();
    await _screenshotCapturer.dispose(); // Releases native cached resources

    _logger.debug('Coordinator disposed', tag: 'coordinator');
  }
}

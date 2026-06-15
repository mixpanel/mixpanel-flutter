import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'models/debug_overlay_colors.dart';
import 'models/results.dart';
import 'models/masking_directive.dart';
import 'session_replay_options.dart';
import 'internal/endpoints.dart';
import 'internal/native_image_compressor.dart';
import 'internal/screenshot_capturer.dart';
import 'internal/event_recorder.dart';
import 'internal/storage/event_queue_interface.dart';
import 'internal/storage/sqlite_event_queue.dart';
import 'internal/session/session_manager.dart';
import 'internal/upload/upload_service.dart';
import 'internal/upload/payload_serializer.dart';
import 'internal/settings/settings_service.dart';
import 'internal/settings/settings_storage_provider.dart';
import 'internal/session_replay_coordinator.dart';
import 'internal/logger.dart';

/// Mixpanel Session Replay for Flutter
class MixpanelSessionReplay {
  /// Registry of active instances by token
  /// Prevents database conflicts when re-initializing with same token
  static final Map<String, MixpanelSessionReplay> _instances = {};

  late SessionReplayCoordinator _coordinator;
  late http.Client _httpClient;
  final MixpanelLogger _logger;
  final String _token;

  /// Current distinct ID (can be updated at runtime)
  String _distinctId;

  MixpanelSessionReplay._internal({
    required MixpanelLogger logger,
    required String token,
    required String distinctId,
  }) : _logger = logger,
       _token = token,
       _distinctId = distinctId;

  /// Initialize Mixpanel Session Replay
  ///
  /// This is the main entry point for the SDK. Call this once during app startup.
  ///
  /// Required parameters:
  /// - [token]: Your Mixpanel project token
  /// - [distinctId]: Unique identifier for the user
  ///
  /// Optional:
  /// - [options]: Configuration options (uses sensible defaults)
  ///
  /// Returns [InitializationResult] containing the instance on success or error details
  static Future<InitializationResult<MixpanelSessionReplay>> initialize({
    required String token,
    required String distinctId,
    SessionReplayOptions options = const SessionReplayOptions(),
  }) async {
    return initializeWithDependencies(
      token: token,
      distinctId: distinctId,
      options: options,
      eventQueue: null, // Use default SqliteEventQueue
    );
  }

  /// Internal initialization with dependency injection for testing
  ///
  /// **INTERNAL USE ONLY** - This method is NOT part of the public API and should
  /// only be used by unit tests. The API may change without notice.
  ///
  /// DO NOT use this method in production code. Use [initialize] instead.
  ///
  /// Allows injecting [EventQueue] and [http.Client] for testing without
  /// requiring platform channels or real network calls.
  /// When [eventQueue] is null, creates SqliteEventQueue (production behavior).
  /// When [httpClient] is null, creates default http.Client (production behavior).
  @visibleForTesting
  static Future<InitializationResult<MixpanelSessionReplay>>
  initializeWithDependencies({
    required String token,
    required String distinctId,
    SessionReplayOptions options = const SessionReplayOptions(),
    EventQueue? eventQueue,
    http.Client? httpClient,
  }) async {
    // Create logger instance for this SDK instance
    final logger = MixpanelLogger(options.logLevel);

    logger.info('Initializing SDK...');
    logger.debug(
      'Token: ${token.length > 8 ? token.substring(0, 8) : token}...',
    );
    logger.debug('DistinctId: $distinctId');
    logger.debug('WiFi Only: ${options.platformOptions.mobile.wifiOnly}');
    logger.debug('Flush Interval: ${options.flushInterval.inSeconds}s');

    try {
      logger.debug('Validating configuration...');
      // Validate configuration parameters
      try {
        if (token.isEmpty) {
          throw ArgumentError('token cannot be empty');
        }

        if (options.autoRecordSessionsPercent < 0 ||
            options.autoRecordSessionsPercent > 100) {
          throw ArgumentError(
            'autoRecordSessionsPercent must be between 0 and 100',
          );
        }

        if (options.storageQuotaMB <= 0) {
          throw ArgumentError('storageQuotaMB must be positive');
        }

        logger.debug('Configuration valid');
      } catch (e) {
        logger.error('Configuration invalid: $e');
        return InitializationResult.failure(
          InitializationError.invalidToken,
          e.toString(),
        );
      }

      // Validate serverUrl. Matches Android: trim whitespace, require
      // https://, require a parseable absolute URL with a host. Paths on the
      // base URL are preserved (not rejected) so proxy URLs like
      // `https://proxy.example.com/mp` are valid.
      final serverUrlValidation = validateServerUrl(options.serverUrl);
      final String resolvedServerUrl;
      switch (serverUrlValidation) {
        case ServerUrlValid(:final trimmedUrl):
          resolvedServerUrl = trimmedUrl;
        case ServerUrlInvalid(:final message):
          logger.error(
            'Invalid serverUrl, Session Replay is disabled: $message',
          );
          return InitializationResult.failure(
            InitializationError.invalidServerUrl,
            message,
          );
      }

      // Enforce App Sandbox on macOS — screenshots are stored locally and must
      // be protected from other processes reading them.
      // Skip when eventQueue is injected (unit tests don't store real screenshots).
      if (eventQueue == null &&
          Platform.isMacOS &&
          !Platform.environment.containsKey('APP_SANDBOX_CONTAINER_ID')) {
        const message =
            'macOS App Sandbox is required for Session Replay. '
            'Enable com.apple.security.app-sandbox in your entitlements file.';
        logger.error(message);
        return InitializationResult.failure(
          InitializationError.platformSecurityNotMet,
          message,
        );
      }

      // Clean up existing instance with this token (prevents database conflicts)
      if (_instances.containsKey(token)) {
        final oldInstance = _instances[token]!;
        logger.info(
          'Re-initializing - disposing old instance for token ${token.length > 8 ? token.substring(0, 8) : token}...',
        );

        // Dispose handles flush + cleanup + registry removal
        await oldInstance._dispose();

        logger.debug('Old instance cleaned up');
      }

      // Initialize event queue (use injected or create SqliteEventQueue)
      logger.debug('Creating event queue...');
      final EventQueue queue =
          eventQueue ??
          SqliteEventQueue(
            token: token,
            quotaMB: options.storageQuotaMB,
            logger: logger,
          );
      await queue.initialize();
      logger.debug('Event queue initialized');

      // Clear all data on app launch
      await queue.removeAll();
      logger.debug('Cleared all existing data');

      // Create internal components
      logger.debug('Creating internal components...');

      // Create session manager
      final sessionManager = SessionManager();

      // Create masking directive from options
      final directive = MaskingDirective(
        autoMaskTypes: options.autoMaskedViews,
      );

      // Create screenshot capturer with native JPEG compression
      final screenshotCapturer = ScreenshotCapturer(
        directive: directive,
        logger: logger,
        debugOverlayEnabled: options.debugOptions?.overlayColors != null,
        nativeCompressor: NativeImageCompressor(),
      );

      // Create instance first (before components) so we can reference it in closures
      final instance = MixpanelSessionReplay._internal(
        logger: logger,
        token: token,
        distinctId: distinctId,
      );

      // Create event recorder (handles both screenshots and interactions)
      final eventRecorder = EventRecorder(
        eventQueue: queue,
        sessionManager: sessionManager,
        getDistinctId: () => instance.distinctId,
        logger: logger,
      );

      // Create settings service (check will happen on first foreground)
      final storageProvider = SettingsStorageProvider(
        token: token,
        logger: logger,
      );
      // Create shared HTTP client (each service borrows it; SDK owns the lifecycle)
      final sharedHttpClient = httpClient ?? http.Client();

      final settingsService = SettingsService(
        token: token,
        logger: logger,
        httpClient: sharedHttpClient,
        storageProvider: storageProvider,
        serverUrl: resolvedServerUrl,
      );

      // Create upload service with payload serializer
      final payloadSerializer = PayloadSerializer(token);
      final uploadService = UploadService(
        eventQueue: queue,
        payloadSerializer: payloadSerializer,
        wifiOnly: options.platformOptions.mobile.wifiOnly,
        getRemoteEnablementState: () => settingsService.remoteState,
        flushInterval: options.flushInterval,
        logger: logger,
        httpClient: sharedHttpClient,
        serverUrl: resolvedServerUrl,
      );

      logger.debug('Internal components created');

      // Create coordinator with all internal components
      // Note: CaptureScheduler is now owned by FrameMonitor widget
      logger.debug('Creating coordinator...');
      final coordinator = SessionReplayCoordinator(
        screenshotCapturer: screenshotCapturer,
        eventRecorder: eventRecorder,
        uploadService: uploadService,
        settingsService: settingsService,
        sessionManager: sessionManager,
        logger: logger,
        autoRecordSessionsPercent: options.autoRecordSessionsPercent,
        remoteSettingsMode: options.remoteSettingsMode,
        debugOptions: options.debugOptions,
      );

      // Wire up the coordinator and shared HTTP client to the instance
      instance._coordinator = coordinator;
      instance._httpClient = sharedHttpClient;

      // Register instance in registry
      _instances[token] = instance;

      logger.info('Initialization successful!');
      return InitializationResult.success(instance);
    } catch (e) {
      logger.error('Initialization failed: $e');
      return InitializationResult.failure(
        InitializationError.storageFailure,
        'Initialization failed: $e',
      );
    }
  }

  /// Start recording session replay
  ///
  /// Optional [sessionsPercent]: Percentage of sessions to record (0-100).
  /// Defaults to 100% (always record).
  ///
  /// If autoStartRecording is true, startRecording will be called when the app is foregrounded.
  void startRecording({double sessionsPercent = 100.0}) {
    _coordinator.startRecording(sessionsPercent: sessionsPercent);
  }

  /// Stop recording session replay
  ///
  /// Disables recording state and stops all active capturing.
  /// Any queued events will still be uploaded.
  ///
  /// Note: If autoStartRecording is enabled, recording will automatically
  /// restart when the app returns to foreground (creating a new session).
  /// If you want to permanently disable recording, set autoStartRecording
  /// to false during initialization.
  ///
  /// Call startRecording() to manually resume recording.
  void stopRecording() {
    _logger.info('Disabling recording');
    _coordinator.stopRecording();
  }

  /// Get the replay ID of the current recording session
  ///
  /// Returns the session's replay ID if recording is in progress, or null
  /// if not currently recording.
  ///
  /// This is the same ID that gets automatically attached as `$mp_replay_id`
  /// to Mixpanel events tracked via the main Mixpanel SDK.
  String? get replayId => _coordinator.replayId;

  /// Current recording state
  ///
  /// Use this to understand the current state of session replay recording:
  /// - [RecordingState.notRecording]: Not recording (initial state or after stop)
  /// - [RecordingState.initializing]: Sampling passed, setting up session
  /// - [RecordingState.recording]: Actively capturing screenshots and interactions
  ///
  /// Example:
  /// ```dart
  /// if (sessionReplay.recordingState == RecordingState.recording) {
  ///   print('Session replay is active');
  /// }
  /// ```
  RecordingState get recordingState => _coordinator.recordingState;

  /// Whether the SDK is allowed to evaluate tracked events against
  /// Event Triggers.
  ///
  /// Reflects the user-controlled toggle set via [enableEventTriggers] /
  /// [disableEventTriggers]; defaults to `true` on SDK initialization.
  ///
  /// `true` means "not opted out" — it does NOT imply triggers are
  /// actually being evaluated. Evaluation additionally requires:
  /// - Remote settings to be enabled (see
  ///   [SessionReplayOptions.remoteSettingsMode]), and
  /// - The remote settings response to include one or more Event Triggers.
  ///
  /// When `false`, any tracked events that would otherwise match a
  /// configured Event Trigger are ignored.
  bool get isEventTriggersEnabled => _coordinator.isEventTriggersEnabled;

  /// Opt out of evaluating tracked events against Event Triggers.
  ///
  /// While opted out, the SDK ignores tracked events that would otherwise
  /// match a server-configured Event Trigger and start a recording. This
  /// is a no-op in cases where no triggers would be evaluated anyway —
  /// for example, when [SessionReplayOptions.remoteSettingsMode] is
  /// [RemoteSettingsMode.disabled], or when the remote settings response
  /// contained no Event Triggers.
  ///
  /// Does not affect:
  /// - Manual recording via [startRecording] / [stopRecording]
  /// - Auto-record on app foreground
  /// - Remote settings parsing or trigger configuration delivery
  ///
  /// Resets to enabled on SDK re-initialization.
  void disableEventTriggers() => _coordinator.disableEventTriggers();

  /// Opt back in to evaluating tracked events against Event Triggers
  /// (the default at SDK initialization).
  ///
  /// Calling this does not by itself cause any triggers to be evaluated:
  /// that still requires remote settings to be enabled and the settings
  /// response to include one or more Event Triggers.
  void enableEventTriggers() => _coordinator.enableEventTriggers();

  /// Get current distinct ID
  String get distinctId => _distinctId;

  /// Identify the user with a new distinct ID
  ///
  /// This will affect all future events - they will be associated with the new distinctId.
  /// Events already captured will retain their original distinctId.
  ///
  /// Example:
  /// ```dart
  /// sessionReplay.identify('user-123');
  /// ```
  void identify(String distinctId) {
    _logger.info(
      'Identifying user: updating distinctId from $_distinctId to $distinctId',
    );
    _distinctId = distinctId;
  }

  /// Internal coordinator for widget operations
  ///
  /// This is used by MixpanelSessionReplayWidget and should NOT be called directly.
  /// This is internal API only.
  @internal
  SessionReplayCoordinator get coordinator => _coordinator;

  /// Debug options configuration (null = debug disabled)
  ///
  /// This is used by MixpanelSessionReplayWidget and should NOT be called directly.
  /// This is internal API only.
  @internal
  DebugOptions? get debugOptions => _coordinator.debugOptions;

  /// Manually flush events to server
  ///
  /// This triggers an immediate upload of queued events.
  /// Normally uploads happen automatically based on flushInterval.
  ///
  /// Returns a [FlushResult] indicating the operation completed. Note that flush
  /// is a best-effort operation that may partially succeed (some batches uploaded,
  /// others failed due to network conditions).
  ///
  /// Users who don't need to wait for completion can use fire-and-forget:
  /// ```dart
  /// unawaited(sessionReplay.flush());
  /// ```
  ///
  /// Users who need to ensure uploads complete (e.g., before app shutdown) should await:
  /// ```dart
  /// await sessionReplay.flush();
  /// ```
  Future<FlushResult> flush() async {
    return await _coordinator.flush();
  }

  /// Dispose resources and stop all services
  ///
  /// INTERNAL: This is called automatically during re-initialization.
  /// Not exposed to users - the SDK manages its own lifecycle.
  ///
  /// Flushes pending events, then stops timers and closes connections.
  Future<void> _dispose() async {
    _logger.info('Disposing SDK instance');

    // Dispose coordinator (handles flush, stops timers, closes connections)
    await _coordinator.dispose();

    // Close shared HTTP client (after coordinator dispose so flush completes first)
    _httpClient.close();

    // Remove from registry after cleanup is complete
    _instances.remove(_token);

    _logger.debug('SDK instance disposed');
  }
}

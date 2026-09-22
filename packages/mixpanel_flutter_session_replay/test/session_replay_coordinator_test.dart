import 'dart:async';
import 'dart:convert';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:mixpanel_flutter_session_replay/src/internal/session_replay_coordinator.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/event_recorder.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/screenshot_capturer.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/native_image_compressor.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/upload/upload_service.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/settings/settings_service.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/settings/settings_storage_provider.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/upload/payload_serializer.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session/session_manager.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/wireframe/wireframe_emitter.dart';
import 'package:mixpanel_flutter_session_replay/src/models/wireframe.dart';
import 'package:mixpanel_flutter_session_replay/src/models/wireframes_options.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/debug_overlay_colors.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';
import 'package:mixpanel_flutter_session_replay/src/models/results.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session_event.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_http_client.dart';
import 'helpers/in_memory_event_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionReplayCoordinator', () {
    late InMemoryEventQueue eventQueue;
    late SessionManager sessionManager;
    late EventRecorder eventRecorder;
    late UploadService uploadService;
    late SettingsService settingsService;
    late ScreenshotCapturer screenshotCapturer;
    late SettingsStorageProvider storageProvider;
    late MixpanelLogger logger;
    late String currentDistinctId;

    SessionReplayCoordinator createCoordinator({
      double autoRecordSessionsPercent = 0,
      RemoteSettingsMode remoteSettingsMode = RemoteSettingsMode.disabled,
      DebugOptions? debugOptions,
      ReplayBackgroundBehavior backgroundBehavior =
          ReplayBackgroundBehavior.stop,
    }) {
      return SessionReplayCoordinator(
        screenshotCapturer: screenshotCapturer,
        eventRecorder: eventRecorder,
        uploadService: uploadService,
        settingsService: settingsService,
        sessionManager: sessionManager,
        logger: logger,
        autoRecordSessionsPercent: autoRecordSessionsPercent,
        remoteSettingsMode: remoteSettingsMode,
        debugOptions: debugOptions,
        backgroundBehavior: backgroundBehavior,
      );
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});

      // Mock the method channel used by SessionReplaySender
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.mixpanel.flutter_session_replay'),
            (call) async => null,
          );

      logger = MixpanelLogger(LogLevel.none);
      storageProvider = SettingsStorageProvider(
        token: 'test-token',
        logger: logger,
      );
      eventQueue = InMemoryEventQueue();
      await eventQueue.initialize();
      sessionManager = SessionManager();

      currentDistinctId = 'user-1';
      eventRecorder = EventRecorder(
        eventQueue: eventQueue,
        sessionManager: sessionManager,
        getDistinctId: () => currentDistinctId,
        logger: logger,
      );

      final httpClient = createFakeHttpClient(statusCode: 200);
      uploadService = UploadService(
        eventQueue: eventQueue,
        payloadSerializer: PayloadSerializer('test-token'),
        wifiOnly: false,
        getRemoteEnablementState: () => RemoteEnablementState.enabled,
        flushInterval: Duration(hours: 1),
        logger: logger,
        httpClient: httpClient,
      );

      settingsService = SettingsService(
        storageProvider: storageProvider,
        token: 'test-token',
        logger: logger,
        httpClient: createFakeSettingsClient(isEnabled: true),
      );

      screenshotCapturer = ScreenshotCapturer(
        directive: MaskingDirective(autoMaskTypes: {}),
        logger: logger,
        debugOverlayEnabled: false,
        compressor: DartPngCompressor(),
      );
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.mixpanel.flutter_session_replay'),
            null,
          );

      try {
        await eventQueue.dispose();
      } catch (_) {
        // Already disposed by test
      }
    });

    group('initial state', () {
      test('starts in notRecording state', () {
        // GIVEN
        final expectedState = RecordingState.notRecording;

        // WHEN
        final coordinator = createCoordinator();

        // THEN
        expect(coordinator.recordingState, expectedState);
      });

      test('starts with app not in foreground', () {
        // GIVEN
        final expectedForeground = false;

        // WHEN
        final coordinator = createCoordinator();

        // THEN - default is false; LifecycleObserver sets true on first resume
        expect(coordinator.isAppInForeground, expectedForeground);
      });

      test('starts with pending remote settings state', () {
        // GIVEN
        final expectedState = RemoteEnablementState.pending;

        // WHEN
        final coordinator = createCoordinator();

        // THEN
        expect(coordinator.remoteEnablementState, expectedState);
      });
    });

    group('startRecording', () {
      test('transitions to recording state with 100% sampling', () async {
        // GIVEN
        final expectedState = RecordingState.recording;
        final coordinator = createCoordinator();

        // WHEN
        coordinator.startRecording(sessionsPercent: 100.0);
        // Wait for async session metadata persistence
        await pumpEventQueue();

        // THEN
        expect(coordinator.recordingState, expectedState);
      });

      test('resets wireframe dedup state so a new session re-emits', () async {
        // GIVEN a capturer wired to a real emitter, primed the way a previous
        // session's last frame would leave it. Dedup is per session, but the
        // emitter is built once in initialize() and survives a stop/start cycle,
        // so without a reset a background/foreground onto an unchanged screen
        // dedups the new session's opening mp_wireframe away — leaving a
        // screenshot with nothing to describe it.
        //
        // Asserted through the coordinator on purpose: a test that calls
        // resetDedup() directly still passes if this call site is deleted.
        final emitter = WireframeEmitter(
          sensitiveRules: const [],
          debugEmitter: null,
          logger: logger,
        );
        screenshotCapturer = ScreenshotCapturer(
          directive: MaskingDirective(autoMaskTypes: {}),
          logger: logger,
          debugOverlayEnabled: false,
          compressor: DartPngCompressor(),
          wireframeEmitter: emitter,
        );

        final frame = [
          const WireframeElement(
            role: WireframeRole.text,
            text: 'unchanged',
            bounds: Rect.fromLTWH(0, 0, 100, 20),
            maskDecision: MaskDecision.none,
          ),
        ];
        WireframePayload? emitFrame() => emitter.emit(
          rawElements: frame,
          maskRegions: const [],
          viewport: const Size(400, 800),
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
        );

        expect(
          emitFrame(),
          isNotNull,
          reason: 'precondition: first emit ships',
        );
        expect(
          emitFrame(),
          isNull,
          reason: 'precondition: an identical frame dedups',
        );

        // WHEN
        final coordinator = createCoordinator();
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();

        // THEN the same screen emits again for the new session.
        expect(
          emitFrame(),
          isNotNull,
          reason:
              'the first frame of a new session must emit even when the screen '
              'has not changed',
        );
      });

      test('does not start when already recording', () async {
        // GIVEN
        final coordinator = createCoordinator();
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();
        expect(coordinator.recordingState, RecordingState.recording);

        // WHEN - try to start again
        coordinator.startRecording(sessionsPercent: 0);

        // THEN - still recording, no state change
        // This test works because you would not expect recording with a 0%
        expect(coordinator.recordingState, RecordingState.recording);
      });

      test('does not start when remote settings are disabled', () async {
        // GIVEN
        final disabledSettingsService = SettingsService(
          storageProvider: storageProvider,
          token: 'test-token',
          logger: logger,
          httpClient: createFakeSettingsClient(isEnabled: false),
        );

        final coordinator = SessionReplayCoordinator(
          screenshotCapturer: screenshotCapturer,
          eventRecorder: eventRecorder,
          uploadService: uploadService,
          settingsService: disabledSettingsService,
          sessionManager: sessionManager,
          logger: logger,
          autoRecordSessionsPercent: 0,
          remoteSettingsMode: RemoteSettingsMode.disabled,
          debugOptions: null,
          backgroundBehavior: ReplayBackgroundBehavior.stop,
        );

        // Trigger settings check via foreground
        coordinator.onAppForegrounded();
        await pumpEventQueue();
        expect(
          coordinator.remoteEnablementState,
          RemoteEnablementState.disabled,
        );

        // WHEN - try to start recording after settings are disabled
        coordinator.startRecording(sessionsPercent: 100.0);

        // THEN - should not be recording (blocked by disabled settings)
        expect(coordinator.recordingState, RecordingState.notRecording);
      });

      test('stays in notRecording with 0% sampling', () {
        // GIVEN
        final expectedState = RecordingState.notRecording;
        final coordinator = createCoordinator();

        // WHEN
        coordinator.startRecording(sessionsPercent: 0.0);

        // THEN
        expect(coordinator.recordingState, expectedState);
      });
    });

    group('stopRecording', () {
      test('transitions to notRecording state', () async {
        // GIVEN
        final expectedState = RecordingState.notRecording;
        final coordinator = createCoordinator();
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();

        // WHEN
        coordinator.stopRecording();

        // THEN
        expect(coordinator.recordingState, expectedState);
      });

      test('is safe to call when not recording', () {
        // GIVEN
        final coordinator = createCoordinator();

        // WHEN / THEN - should not throw
        coordinator.stopRecording();
        expect(coordinator.recordingState, RecordingState.notRecording);
      });

      test('allows restarting after stop', () async {
        // GIVEN - start and then stop recording
        final coordinator = createCoordinator();
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();
        expect(coordinator.recordingState, RecordingState.recording);
        coordinator.stopRecording();
        expect(coordinator.recordingState, RecordingState.notRecording);

        // WHEN - start recording again from notRecording state
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();

        // THEN - should be recording again
        expect(coordinator.recordingState, RecordingState.recording);
      });
    });

    group('captureInteraction', () {
      test('records interaction when recording is active', () async {
        // GIVEN
        final expectedInteractionType = 7;
        final expectedX = 100.0;
        final expectedY = 200.0;
        final coordinator = createCoordinator();
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();

        // WHEN
        coordinator.captureInteraction(
          expectedInteractionType,
          Offset(expectedX, expectedY),
          DateTime.now(),
        );
        // Wait for async event recording
        await pumpEventQueue();

        // THEN
        final oldest = await eventQueue.fetchOldest();
        expect(oldest, isNotNull);
        // Should find the interaction event (after metadata)
        final events = await eventQueue.fetchBatch(
          sessionId: oldest!.sessionId,
          distinctId: oldest.distinctId,
          maxBytes: 100000,
          maxCount: 10,
        );
        final interactionEvents = events
            .where((e) => e.type == EventType.interaction)
            .toList();
        expect(interactionEvents.length, 1);

        final payload = interactionEvents[0].payload as InteractionPayload;
        expect(payload.interactionType, expectedInteractionType);
        expect(payload.x, expectedX);
        expect(payload.y, expectedY);
      });

      test('skips interaction when not recording', () async {
        // GIVEN
        final coordinator = createCoordinator();
        // Don't start recording

        // WHEN
        coordinator.captureInteraction(7, Offset(100, 200), DateTime.now());
        await pumpEventQueue();

        // THEN
        final oldest = await eventQueue.fetchOldest();
        expect(oldest, isNull);
      });

      test('skips interaction when disposed', () async {
        // GIVEN
        final coordinator = createCoordinator();
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();
        await coordinator.dispose();

        // WHEN
        coordinator.captureInteraction(7, Offset(100, 200), DateTime.now());
        await pumpEventQueue();

        // THEN - queue is disposed, operations should throw
        expect(() => eventQueue.fetchOldest(), throwsA(anything));
      });
    });

    group('captureTouchMove', () {
      test('records a position batch when recording is active', () async {
        // GIVEN
        final expectedPositions = const [
          TouchPosition(x: 10.0, y: 20.0, timeOffset: -100),
          TouchPosition(x: 30.0, y: 40.0, timeOffset: 0),
        ];
        final coordinator = createCoordinator();
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();

        // WHEN
        coordinator.captureTouchMove(expectedPositions, DateTime.now());
        await pumpEventQueue();

        // THEN
        final oldest = await eventQueue.fetchOldest();
        final events = await eventQueue.fetchBatch(
          sessionId: oldest!.sessionId,
          distinctId: oldest.distinctId,
          maxBytes: 100000,
          maxCount: 10,
        );
        final touchMoves = events
            .where((e) => e.type == EventType.touchMove)
            .toList();
        expect(touchMoves.length, 1);
        expect(
          (touchMoves[0].payload as TouchMovePayload).positions,
          expectedPositions,
        );
      });

      test('skips touch move when not recording', () async {
        // GIVEN
        final coordinator = createCoordinator();
        // Don't start recording

        // WHEN
        coordinator.captureTouchMove(const [
          TouchPosition(x: 1, y: 2, timeOffset: 0),
        ], DateTime.now());
        await pumpEventQueue();

        // THEN
        expect(await eventQueue.fetchOldest(), isNull);
      });
    });

    group('onAppBackgrounded', () {
      test('marks app as not in foreground', () {
        // GIVEN
        final coordinator = createCoordinator();

        // WHEN
        coordinator.onAppBackgrounded();

        // THEN
        expect(coordinator.isAppInForeground, false);
      });

      test('pauses recording when app goes to background', () async {
        // GIVEN
        final coordinator = createCoordinator(
          backgroundBehavior: const ReplayBackgroundBehavior.pause(
            idleTimeout: Duration(minutes: 30),
          ),
        );
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();
        expect(coordinator.recordingState, RecordingState.recording);
        coordinator.captureInteraction(2, const Offset(10, 20), DateTime.now());
        await pumpEventQueue();
        expect(await eventQueue.fetchOldest(), isNotNull);

        // WHEN
        coordinator.onAppBackgrounded();
        await pumpEventQueue();

        // THEN
        expect(coordinator.recordingState, RecordingState.paused);
        expect(await eventQueue.fetchOldest(), isNull);
      });

      test(
        'resumes the same session when metadata finishes while backgrounded',
        () async {
          // GIVEN a session whose metadata write has started but has not yet
          // completed its asynchronous callback.
          final coordinator = createCoordinator(
            autoRecordSessionsPercent: 100,
            backgroundBehavior: const ReplayBackgroundBehavior.pause(
              idleTimeout: Duration(minutes: 30),
            ),
          );
          coordinator.startRecording(sessionsPercent: 100);
          final sessionId = sessionManager.getCurrentSession().id;
          expect(coordinator.recordingState, RecordingState.initializing);

          // WHEN the app backgrounds before the callback, then returns.
          coordinator.onAppBackgrounded();
          expect(coordinator.recordingState, RecordingState.paused);
          coordinator.onAppForegrounded();
          await pumpEventQueue();

          // THEN the existing session resumes; no metadata latch is required.
          expect(coordinator.recordingState, RecordingState.recording);
          expect(sessionManager.getCurrentSession().id, sessionId);
        },
      );

      test('is safe to call when disposed', () async {
        // GIVEN
        final coordinator = createCoordinator();
        await coordinator.dispose();

        // WHEN / THEN - should not throw
        coordinator.onAppBackgrounded();
      });
    });

    group('onAppForegrounded', () {
      test('marks app as in foreground', () {
        // GIVEN
        final coordinator = createCoordinator();
        expect(coordinator.isAppInForeground, false);

        // WHEN
        coordinator.onAppForegrounded();

        // THEN
        expect(coordinator.isAppInForeground, true);
      });

      test(
        'auto-starts recording after settings resolve when autoRecordSessionsPercent > 0',
        () async {
          // GIVEN
          final coordinator = createCoordinator(
            autoRecordSessionsPercent: 100.0,
          );

          // WHEN - foreground triggers settings check, then auto-start
          coordinator.onAppForegrounded();
          await pumpEventQueue();

          // THEN - recording starts after settings resolve
          expect(
            coordinator.remoteEnablementState,
            RemoteEnablementState.enabled,
          );
          expect(coordinator.recordingState, RecordingState.recording);
        },
      );

      test('does not auto-start when autoRecordSessionsPercent is 0', () async {
        // GIVEN
        final coordinator = createCoordinator(autoRecordSessionsPercent: 0);
        coordinator.onAppBackgrounded();

        // WHEN
        coordinator.onAppForegrounded();
        await pumpEventQueue();

        // THEN
        expect(coordinator.recordingState, RecordingState.notRecording);
      });

      test('checks remote settings on first foreground', () async {
        // GIVEN
        final coordinator = createCoordinator();
        expect(
          coordinator.remoteEnablementState,
          RemoteEnablementState.pending,
        );

        // WHEN
        coordinator.onAppForegrounded();
        // Wait for async settings check
        await pumpEventQueue();

        // THEN
        expect(
          coordinator.remoteEnablementState,
          RemoteEnablementState.enabled,
        );
      });

      test(
        'does not auto-start recording when remote enablement is disabled',
        () async {
          // GIVEN
          final disabledSettingsService = SettingsService(
            storageProvider: storageProvider,
            token: 'test-token',
            logger: logger,
            httpClient: createFakeSettingsClient(isEnabled: false),
          );

          final coordinator = SessionReplayCoordinator(
            screenshotCapturer: screenshotCapturer,
            eventRecorder: eventRecorder,
            uploadService: uploadService,
            settingsService: disabledSettingsService,
            sessionManager: sessionManager,
            logger: logger,
            autoRecordSessionsPercent: 100.0,
            remoteSettingsMode: RemoteSettingsMode.disabled,
            debugOptions: null,
            backgroundBehavior: ReplayBackgroundBehavior.stop,
          );

          // WHEN
          coordinator.onAppForegrounded();
          await pumpEventQueue();

          // THEN - remote enablement prevents recording from ever starting
          expect(
            coordinator.remoteEnablementState,
            RemoteEnablementState.disabled,
          );
          expect(coordinator.recordingState, RecordingState.notRecording);
        },
      );

      test('is safe to call when disposed', () async {
        // GIVEN
        final coordinator = createCoordinator();
        await coordinator.dispose();

        // WHEN / THEN - should not throw
        coordinator.onAppForegrounded();
      });
    });

    group('dispose', () {
      test('prevents further interactions from being recorded', () async {
        // GIVEN
        final coordinator = createCoordinator();
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();

        // WHEN
        await coordinator.dispose();

        // THEN - captureInteraction is a no-op
        coordinator.captureInteraction(7, Offset(100, 200), DateTime.now());
        // Event queue is disposed so we can't check it,
        // but the call should not throw
      });

      test('is safe to call stopRecording after dispose', () async {
        // GIVEN
        final coordinator = createCoordinator();
        await coordinator.dispose();

        // WHEN / THEN - should not throw
        coordinator.stopRecording();
      });

      test('is safe to call startRecording after dispose', () async {
        // GIVEN
        final coordinator = createCoordinator();
        await coordinator.dispose();

        // WHEN / THEN - should not throw
        coordinator.startRecording(sessionsPercent: 100.0);
      });

      test('resets recordingState to notRecording', () async {
        // GIVEN - coordinator is actively recording
        final coordinator = createCoordinator();
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();
        expect(coordinator.recordingState, RecordingState.recording);

        // WHEN
        await coordinator.dispose();

        // THEN
        expect(coordinator.recordingState, RecordingState.notRecording);
      });
    });

    group('getters', () {
      test('logger getter returns logger instance', () {
        // GIVEN
        final coordinator = createCoordinator();

        // WHEN / THEN
        expect(coordinator.logger, isNotNull);
        expect(coordinator.logger, same(logger));
      });

      test('debugOptions returns null when not set', () {
        // GIVEN
        final coordinator = createCoordinator();

        // WHEN / THEN
        expect(coordinator.debugOptions, isNull);
      });

      test('maskRegionsNotifier returns a ValueNotifier', () {
        // GIVEN
        final coordinator = createCoordinator();

        // WHEN / THEN
        expect(coordinator.maskRegionsNotifier, isNotNull);
        expect(coordinator.maskRegionsNotifier.value, isEmpty);
      });
    });

    group('settings error handling', () {
      test('network error with no cache defaults to enabled', () async {
        // GIVEN - settings service that fails with no cached values
        final errorSettingsService = SettingsService(
          storageProvider: storageProvider,
          token: 'test-token',
          logger: logger,
          httpClient: createFailingHttpClient(),
        );

        final coordinator = SessionReplayCoordinator(
          screenshotCapturer: screenshotCapturer,
          eventRecorder: eventRecorder,
          uploadService: uploadService,
          settingsService: errorSettingsService,
          sessionManager: sessionManager,
          logger: logger,
          autoRecordSessionsPercent: 0,
          remoteSettingsMode: RemoteSettingsMode.disabled,
          debugOptions: null,
          backgroundBehavior: ReplayBackgroundBehavior.stop,
        );

        // WHEN
        coordinator.onAppForegrounded();
        await pumpEventQueue();

        // THEN - no cache, so defaults to enabled
        expect(
          coordinator.remoteEnablementState,
          RemoteEnablementState.enabled,
        );
      });

      test(
        'strict mode disables recording when network fails (from cache)',
        () async {
          // GIVEN - settings service that fails with no cache
          final errorSettingsService = SettingsService(
            storageProvider: storageProvider,
            token: 'test-token',
            logger: logger,
            httpClient: createFailingHttpClient(),
          );

          final coordinator = SessionReplayCoordinator(
            screenshotCapturer: screenshotCapturer,
            eventRecorder: eventRecorder,
            uploadService: uploadService,
            settingsService: errorSettingsService,
            sessionManager: sessionManager,
            logger: logger,
            autoRecordSessionsPercent: 100.0,
            remoteSettingsMode: RemoteSettingsMode.strict,
            debugOptions: null,
            backgroundBehavior: ReplayBackgroundBehavior.stop,
          );

          // WHEN - foreground triggers settings check which falls back to cache
          coordinator.onAppForegrounded();
          await pumpEventQueue();

          // THEN - strict mode: fromCache=true → disables recording
          expect(
            coordinator.remoteEnablementState,
            RemoteEnablementState.disabled,
          );
          expect(coordinator.recordingState, RecordingState.notRecording);
        },
      );

      test(
        'remote enablement stops manually started recording when settings arrive',
        () async {
          // GIVEN - delayed settings response
          final completer = Completer<http.Response>();
          final delayedSettingsService = SettingsService(
            storageProvider: storageProvider,
            token: 'test-token',
            logger: logger,
            httpClient: http_testing.MockClient((_) => completer.future),
          );

          final coordinator = SessionReplayCoordinator(
            screenshotCapturer: screenshotCapturer,
            eventRecorder: eventRecorder,
            uploadService: uploadService,
            settingsService: delayedSettingsService,
            sessionManager: sessionManager,
            logger: logger,
            autoRecordSessionsPercent: 0,
            remoteSettingsMode: RemoteSettingsMode.disabled,
            debugOptions: null,
            backgroundBehavior: ReplayBackgroundBehavior.stop,
          );

          // Trigger settings check (in-flight)
          coordinator.onAppForegrounded();

          // Manually start recording while settings check is pending
          coordinator.startRecording(sessionsPercent: 100.0);
          await pumpEventQueue();
          expect(coordinator.recordingState, RecordingState.recording);

          // WHEN - remote enablement returns disabled
          completer.complete(
            http.Response(
              jsonEncode({
                'recording': {'is_enabled': false},
              }),
              200,
            ),
          );
          await pumpEventQueue();

          // THEN - remote enablement stops the in-progress recording
          expect(
            coordinator.remoteEnablementState,
            RemoteEnablementState.disabled,
          );
          expect(coordinator.recordingState, RecordingState.notRecording);
        },
      );

      test(
        'already-enabled settings starts upload service on subsequent foreground',
        () async {
          // GIVEN - first foreground sets settings to enabled
          final coordinator = createCoordinator();
          coordinator.onAppForegrounded();
          await pumpEventQueue();
          expect(
            coordinator.remoteEnablementState,
            RemoteEnablementState.enabled,
          );

          // Background then foreground again
          coordinator.onAppBackgrounded();

          // WHEN - second foreground with settings already enabled
          coordinator.onAppForegrounded();
          await pumpEventQueue();

          // THEN - should not error, upload service started immediately
          expect(
            coordinator.remoteEnablementState,
            RemoteEnablementState.enabled,
          );
          expect(coordinator.isAppInForeground, true);
        },
      );
    });

    group('wireframe kill switch', () {
      // The other platforms clear `wireframesOptions` before building the
      // instance; here the emitter is wired at init and settings land on first
      // foreground, so the coordinator has to stop a live capturer.
      ScreenshotCapturer createWireframeCapturer() => ScreenshotCapturer(
        directive: MaskingDirective(autoMaskTypes: {}),
        logger: logger,
        debugOverlayEnabled: false,
        compressor: DartPngCompressor(),
        wireframeEmitter: WireframeEmitter(
          sensitiveRules: const [],
          debugEmitter: null,
          logger: logger,
        ),
      );

      SessionReplayCoordinator createWireframeCoordinator({
        required ScreenshotCapturer capturer,
        required SettingsService settings,
        RemoteSettingsMode remoteSettingsMode = RemoteSettingsMode.fallback,
      }) => SessionReplayCoordinator(
        screenshotCapturer: capturer,
        eventRecorder: eventRecorder,
        uploadService: uploadService,
        settingsService: settings,
        sessionManager: sessionManager,
        logger: logger,
        autoRecordSessionsPercent: 100.0,
        remoteSettingsMode: remoteSettingsMode,
        debugOptions: null,
        backgroundBehavior: ReplayBackgroundBehavior.stop,
      );

      test('stops wireframe capture when the server disables it', () async {
        // GIVEN - recording allowed, wireframes killed
        final capturer = createWireframeCapturer();
        final coordinator = createWireframeCoordinator(
          capturer: capturer,
          settings: SettingsService(
            storageProvider: storageProvider,
            token: 'test-token',
            logger: logger,
            httpClient: createFakeSettingsClient(
              isEnabled: true,
              wireframeEnabled: false,
              wireframeError: 'organization is blocked from wireframe capture.',
            ),
            wireframesRequested: true,
          ),
        );

        // WHEN
        coordinator.onAppForegrounded();
        await pumpEventQueue();

        // THEN - replay keeps recording, only wireframes are off
        expect(capturer.wireframesEnabled, false);
        expect(coordinator.recordingState, RecordingState.recording);
      });

      test('suppresses wireframes until the verdict arrives', () async {
        // GIVEN - wireframes opted in locally, settings not fetched yet
        final capturer = createWireframeCapturer();
        createWireframeCoordinator(
          capturer: capturer,
          settings: SettingsService(
            storageProvider: storageProvider,
            token: 'test-token',
            logger: logger,
            httpClient: createFakeSettingsClient(
              isEnabled: true,
              wireframeEnabled: true,
            ),
            wireframesRequested: true,
          ),
        );

        // THEN - a manually started recording cannot ship a wireframe yet
        expect(capturer.wireframesEnabled, false);
      });

      test('leaves wireframe capture on when the field is absent', () async {
        // GIVEN - a server that was never asked for the switch
        final capturer = createWireframeCapturer();
        final coordinator = createWireframeCoordinator(
          capturer: capturer,
          settings: SettingsService(
            storageProvider: storageProvider,
            token: 'test-token',
            logger: logger,
            httpClient: createFakeSettingsClient(isEnabled: true),
          ),
        );

        // WHEN
        coordinator.onAppForegrounded();
        await pumpEventQueue();

        // THEN
        expect(capturer.wireframesEnabled, true);
      });

      test('honors the kill switch in disabled remote settings mode', () async {
        // GIVEN - remote config is ignored, but enablement switches are not
        final capturer = createWireframeCapturer();
        final coordinator = createWireframeCoordinator(
          capturer: capturer,
          remoteSettingsMode: RemoteSettingsMode.disabled,
          settings: SettingsService(
            storageProvider: storageProvider,
            token: 'test-token',
            logger: logger,
            httpClient: createFakeSettingsClient(
              isEnabled: true,
              wireframeEnabled: false,
            ),
            wireframesRequested: true,
          ),
        );

        // WHEN
        coordinator.onAppForegrounded();
        await pumpEventQueue();

        // THEN
        expect(capturer.wireframesEnabled, false);
      });

      test('honors the kill switch when recording is also disabled', () async {
        // GIVEN - both switches off
        final capturer = createWireframeCapturer();
        final coordinator = createWireframeCoordinator(
          capturer: capturer,
          settings: SettingsService(
            storageProvider: storageProvider,
            token: 'test-token',
            logger: logger,
            httpClient: createFakeSettingsClient(
              isEnabled: false,
              wireframeEnabled: false,
            ),
            wireframesRequested: true,
          ),
        );

        // WHEN
        coordinator.onAppForegrounded();
        await pumpEventQueue();

        // THEN
        expect(capturer.wireframesEnabled, false);
        expect(coordinator.recordingState, RecordingState.notRecording);
      });
    });

    group('remote config modes', () {
      test('disabled mode ignores remote sdk_config values', () async {
        // GIVEN - server returns 25% sampling rate
        final remoteSettingsService = SettingsService(
          storageProvider: storageProvider,
          token: 'test-token',
          logger: logger,
          httpClient: createFakeSettingsClient(
            isEnabled: true,
            recordSessionsPercent: 25.0,
          ),
        );

        final coordinator = SessionReplayCoordinator(
          screenshotCapturer: screenshotCapturer,
          eventRecorder: eventRecorder,
          uploadService: uploadService,
          settingsService: remoteSettingsService,
          sessionManager: sessionManager,
          logger: logger,
          autoRecordSessionsPercent: 100.0, // local config
          remoteSettingsMode: RemoteSettingsMode.disabled,
          debugOptions: null,
          backgroundBehavior: ReplayBackgroundBehavior.stop,
        );

        // WHEN - foreground triggers settings check
        coordinator.onAppForegrounded();
        await pumpEventQueue();

        // THEN - remote settings enabled, but sdk_config ignored
        expect(
          coordinator.remoteEnablementState,
          RemoteEnablementState.enabled,
        );
        // Recording should start with local 100% (always records)
        expect(coordinator.recordingState, RecordingState.recording);
      });

      test('fallback mode applies remote recordSessionsPercent', () async {
        // GIVEN - server returns 0% sampling rate (disable auto-recording)
        final remoteSettingsService = SettingsService(
          storageProvider: storageProvider,
          token: 'test-token',
          logger: logger,
          httpClient: createFakeSettingsClient(
            isEnabled: true,
            recordSessionsPercent: 0.0,
          ),
        );

        final coordinator = SessionReplayCoordinator(
          screenshotCapturer: screenshotCapturer,
          eventRecorder: eventRecorder,
          uploadService: uploadService,
          settingsService: remoteSettingsService,
          sessionManager: sessionManager,
          logger: logger,
          autoRecordSessionsPercent: 100.0, // local config
          remoteSettingsMode: RemoteSettingsMode.fallback,
          debugOptions: null,
          backgroundBehavior: ReplayBackgroundBehavior.stop,
        );

        // WHEN - foreground triggers settings check, then auto-start
        coordinator.onAppForegrounded();
        await pumpEventQueue();

        // THEN - remote 0% overrides local 100%, recording does not start
        expect(
          coordinator.remoteEnablementState,
          RemoteEnablementState.enabled,
        );
        expect(coordinator.recordingState, RecordingState.notRecording);
      });

      test('strict mode disables when sdk_config is missing', () async {
        // GIVEN - server returns enabled but no sdk_config
        final remoteSettingsService = SettingsService(
          storageProvider: storageProvider,
          token: 'test-token',
          logger: logger,
          httpClient: createFakeSettingsClient(isEnabled: true),
        );

        final coordinator = SessionReplayCoordinator(
          screenshotCapturer: screenshotCapturer,
          eventRecorder: eventRecorder,
          uploadService: uploadService,
          settingsService: remoteSettingsService,
          sessionManager: sessionManager,
          logger: logger,
          autoRecordSessionsPercent: 100.0,
          remoteSettingsMode: RemoteSettingsMode.strict,
          debugOptions: null,
          backgroundBehavior: ReplayBackgroundBehavior.stop,
        );

        // WHEN - foreground triggers settings check
        coordinator.onAppForegrounded();
        await pumpEventQueue();

        // THEN - strict mode: sdk_config missing → never starts recording
        expect(
          coordinator.remoteEnablementState,
          RemoteEnablementState.disabled,
        );
        expect(coordinator.recordingState, RecordingState.notRecording);
      });

      test(
        'strict mode stops manually started recording when sdk_config is missing',
        () async {
          // GIVEN - delayed settings response so we can start recording
          // while the check is in-flight
          final completer = Completer<http.Response>();
          final delayedSettingsService = SettingsService(
            storageProvider: storageProvider,
            token: 'test-token',
            logger: logger,
            httpClient: http_testing.MockClient((_) => completer.future),
          );

          final coordinator = SessionReplayCoordinator(
            screenshotCapturer: screenshotCapturer,
            eventRecorder: eventRecorder,
            uploadService: uploadService,
            settingsService: delayedSettingsService,
            sessionManager: sessionManager,
            logger: logger,
            autoRecordSessionsPercent: 0, // no auto-start
            remoteSettingsMode: RemoteSettingsMode.strict,
            debugOptions: null,
            backgroundBehavior: ReplayBackgroundBehavior.stop,
          );

          // Trigger settings check (in-flight, not yet resolved)
          coordinator.onAppForegrounded();

          // Manually start recording while settings check is pending
          coordinator.startRecording(sessionsPercent: 100.0);
          await pumpEventQueue();
          expect(coordinator.recordingState, RecordingState.recording);

          // WHEN - settings respond with no sdk_config
          completer.complete(
            http.Response(
              jsonEncode({
                'recording': {'is_enabled': true},
              }),
              200,
            ),
          );
          await pumpEventQueue();

          // THEN - strict mode stops the in-progress recording
          expect(
            coordinator.remoteEnablementState,
            RemoteEnablementState.disabled,
          );
          expect(coordinator.recordingState, RecordingState.notRecording);
        },
      );

      test('strict mode allows recording when sdk_config is present', () async {
        // GIVEN - server returns enabled with sdk_config
        final remoteSettingsService = SettingsService(
          storageProvider: storageProvider,
          token: 'test-token',
          logger: logger,
          httpClient: createFakeSettingsClient(
            isEnabled: true,
            recordSessionsPercent: 100.0,
          ),
        );

        final coordinator = SessionReplayCoordinator(
          screenshotCapturer: screenshotCapturer,
          eventRecorder: eventRecorder,
          uploadService: uploadService,
          settingsService: remoteSettingsService,
          sessionManager: sessionManager,
          logger: logger,
          autoRecordSessionsPercent: 100.0,
          remoteSettingsMode: RemoteSettingsMode.strict,
          debugOptions: null,
          backgroundBehavior: ReplayBackgroundBehavior.stop,
        );

        // WHEN - foreground triggers settings check + auto-start
        coordinator.onAppForegrounded();
        await pumpEventQueue();

        // THEN - strict mode: sdk_config present → allows recording
        expect(
          coordinator.remoteEnablementState,
          RemoteEnablementState.enabled,
        );
        expect(coordinator.recordingState, RecordingState.recording);
      });

      test('fallback mode keeps local config when network fails', () async {
        // GIVEN - network fails
        final errorSettingsService = SettingsService(
          storageProvider: storageProvider,
          token: 'test-token',
          logger: logger,
          httpClient: createFailingHttpClient(),
        );

        final coordinator = SessionReplayCoordinator(
          screenshotCapturer: screenshotCapturer,
          eventRecorder: eventRecorder,
          uploadService: uploadService,
          settingsService: errorSettingsService,
          sessionManager: sessionManager,
          logger: logger,
          autoRecordSessionsPercent: 100.0,
          remoteSettingsMode: RemoteSettingsMode.fallback,
          debugOptions: null,
          backgroundBehavior: ReplayBackgroundBehavior.stop,
        );

        // WHEN - foreground triggers settings check
        coordinator.onAppForegrounded();
        await pumpEventQueue();

        // THEN - fallback mode: network error with no cache → keeps local config
        // isRecordingEnabled defaults to true (no cache), so recording continues
        expect(
          coordinator.remoteEnablementState,
          RemoteEnablementState.enabled,
        );
        expect(coordinator.recordingState, RecordingState.recording);
      });
    });

    group('replayId', () {
      test('returns null when not recording', () {
        // GIVEN
        final coordinator = createCoordinator();

        // WHEN / THEN
        expect(coordinator.replayId, isNull);
      });

      test('returns session ID when recording', () async {
        // GIVEN
        final coordinator = createCoordinator();
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();

        // WHEN
        final replayId = coordinator.replayId;

        // THEN
        expect(replayId, isNotNull);
        expect(replayId, sessionManager.getCurrentSession().id);
      });

      test('returns session ID during initializing state', () {
        // GIVEN
        final coordinator = createCoordinator();

        // WHEN - start recording but don't pump (stays in initializing)
        coordinator.startRecording(sessionsPercent: 100.0);

        // THEN
        expect(coordinator.recordingState, RecordingState.initializing);
        expect(coordinator.replayId, isNotNull);
        expect(coordinator.replayId, sessionManager.getCurrentSession().id);
      });

      test('returns null after stopRecording', () async {
        // GIVEN
        final coordinator = createCoordinator();
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();
        expect(coordinator.replayId, isNotNull);

        // WHEN
        coordinator.stopRecording();

        // THEN
        expect(coordinator.replayId, isNull);
      });

      test('background pause hides and restores the same replay ID', () async {
        // GIVEN
        final coordinator = createCoordinator(
          autoRecordSessionsPercent: 100,
          backgroundBehavior: const ReplayBackgroundBehavior.pause(
            idleTimeout: Duration(minutes: 30),
          ),
        );
        coordinator.onAppForegrounded();
        await pumpEventQueue();
        final replayId = coordinator.replayId;

        // WHEN
        coordinator.onAppBackgrounded();

        // THEN
        expect(coordinator.replayId, isNull);

        // WHEN
        coordinator.onAppForegrounded();

        // THEN
        expect(coordinator.replayId, replayId);
      });

      test('returns new ID after restart', () async {
        // GIVEN
        final coordinator = createCoordinator();
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();
        final firstReplayId = coordinator.replayId;

        // WHEN
        coordinator.stopRecording();
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();
        final secondReplayId = coordinator.replayId;

        // THEN
        expect(firstReplayId, isNotNull);
        expect(secondReplayId, isNotNull);
        expect(secondReplayId, isNot(equals(firstReplayId)));
      });
    });

    group('SessionReplaySender integration', () {
      late List<MethodCall> methodCalls;

      setUp(() {
        methodCalls = [];

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('com.mixpanel.flutter_session_replay'),
              (call) async {
                methodCalls.add(call);
                return null;
              },
            );
      });

      tearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('com.mixpanel.flutter_session_replay'),
              null,
            );
      });

      test('registers \$mp_replay_id on startRecording', () async {
        // GIVEN
        final coordinator = createCoordinator();

        // WHEN
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();

        // THEN
        final registerCalls = methodCalls
            .where((c) => c.method == 'registerSuperProperties')
            .toList();
        expect(registerCalls, hasLength(1));
        final args = registerCalls[0].arguments as Map;
        expect(args['\$mp_replay_id'], sessionManager.getCurrentSession().id);
      });

      test('unregisters \$mp_replay_id on stopRecording', () async {
        // GIVEN
        final coordinator = createCoordinator();
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();

        // WHEN
        coordinator.stopRecording();
        await pumpEventQueue();

        // THEN
        final unregisterCalls = methodCalls
            .where((c) => c.method == 'unregisterSuperProperty')
            .toList();
        expect(unregisterCalls, hasLength(1));
        expect(unregisterCalls[0].arguments, {'key': '\$mp_replay_id'});
      });

      test('does not register when sampling rejects', () async {
        // GIVEN
        final coordinator = createCoordinator();

        // WHEN
        coordinator.startRecording(sessionsPercent: 0.0);
        await pumpEventQueue();

        // THEN
        final registerCalls = methodCalls
            .where((c) => c.method == 'registerSuperProperties')
            .toList();
        expect(registerCalls, isEmpty);
      });

      test('unregisters on app backgrounded', () async {
        // GIVEN
        final coordinator = createCoordinator();
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();

        // WHEN
        coordinator.onAppBackgrounded();
        await pumpEventQueue();

        // THEN
        final unregisterCalls = methodCalls
            .where((c) => c.method == 'unregisterSuperProperty')
            .toList();
        expect(unregisterCalls, hasLength(1));
        expect(unregisterCalls[0].arguments, {'key': '\$mp_replay_id'});
      });

      test(
        'background pause unregisters and foreground re-registers the same replay ID',
        () async {
          // GIVEN
          final coordinator = createCoordinator(
            autoRecordSessionsPercent: 100,
            backgroundBehavior: const ReplayBackgroundBehavior.pause(
              idleTimeout: Duration(minutes: 30),
            ),
          );
          coordinator.onAppForegrounded();
          await pumpEventQueue();
          final replayId = sessionManager.getCurrentSession().id;
          methodCalls.clear();

          // WHEN
          coordinator.onAppBackgrounded();
          await pumpEventQueue();
          coordinator.onAppForegrounded();
          await pumpEventQueue();

          // THEN
          expect(
            methodCalls.where((c) => c.method == 'unregisterSuperProperty'),
            hasLength(1),
          );
          final registerCalls = methodCalls
              .where((c) => c.method == 'registerSuperProperties')
              .toList();
          expect(registerCalls, hasLength(1));
          expect(
            (registerCalls.single.arguments as Map)['\$mp_replay_id'],
            replayId,
          );
        },
      );
    });

    group('stopRecording flush error', () {
      test('does not throw when flush fails during stop', () async {
        // GIVEN - coordinator with recording active
        final coordinator = createCoordinator();
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();

        // Dispose event queue to force flush to error
        await eventQueue.dispose();

        // WHEN / THEN - stopRecording should not throw even if flush fails
        coordinator.stopRecording();
        expect(coordinator.recordingState, RecordingState.notRecording);
      });
    });

    group('recording state machine', () {
      test(
        'full lifecycle: notRecording -> recording -> notRecording',
        () async {
          // GIVEN
          final coordinator = createCoordinator();
          expect(coordinator.recordingState, RecordingState.notRecording);

          // WHEN - start recording
          coordinator.startRecording(sessionsPercent: 100.0);
          await pumpEventQueue();

          // THEN
          expect(coordinator.recordingState, RecordingState.recording);

          // WHEN - stop recording
          coordinator.stopRecording();

          // THEN
          expect(coordinator.recordingState, RecordingState.notRecording);
        },
      );

      test('background/foreground cycle resumes the same session', () async {
        // GIVEN - first foreground resolves settings and starts recording
        final coordinator = createCoordinator(
          autoRecordSessionsPercent: 100.0,
          backgroundBehavior: const ReplayBackgroundBehavior.pause(
            idleTimeout: Duration(minutes: 30),
          ),
        );
        coordinator.onAppForegrounded();
        await pumpEventQueue();
        expect(coordinator.recordingState, RecordingState.recording);
        final firstSession = sessionManager.getCurrentSession();

        // WHEN - background then foreground (settings already resolved)
        coordinator.onAppBackgrounded();
        coordinator.onAppForegrounded();
        await pumpEventQueue();

        // THEN - existing session resumed
        final secondSession = sessionManager.getCurrentSession();
        expect(secondSession.id, firstSession.id);
        expect(coordinator.recordingState, RecordingState.recording);
      });
    });

    group('capture in flight across identity changes', () {
      late _PendingScreenshotCapturer pendingCapturer;
      late _RecordingEventQueue recordingQueue;
      late Element boundaryElement;

      setUp(() async {
        recordingQueue = _RecordingEventQueue();
        await recordingQueue.initialize();
        eventQueue = recordingQueue;
        eventRecorder = EventRecorder(
          eventQueue: recordingQueue,
          sessionManager: sessionManager,
          getDistinctId: () => currentDistinctId,
          logger: logger,
        );
        pendingCapturer = _PendingScreenshotCapturer(logger: logger);
        screenshotCapturer = pendingCapturer;
        boundaryElement = const SizedBox().createElement();
      });

      Future<SessionReplayCoordinator>
      startRecordingWithPendingCapture() async {
        final coordinator = createCoordinator();
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();
        expect(coordinator.recordingState, RecordingState.recording);
        return coordinator;
      }

      test(
        'should record the frame under the captured session when the session rotates during capture',
        () async {
          // GIVEN - a capture is in flight
          final coordinator = await startRecordingWithPendingCapture();
          final capturedSessionId = sessionManager.getCurrentSession().id;
          final capture = coordinator.captureSnapshot(
            RenderRepaintBoundary(),
            boundaryElement: boundaryElement,
          );
          await pumpEventQueue();

          // WHEN - a stop/start cycle rotates the session before it resolves
          coordinator.stopRecording();
          coordinator.startRecording(sessionsPercent: 100.0);
          await pumpEventQueue();
          expect(
            sessionManager.getCurrentSession().id,
            isNot(equals(capturedSessionId)),
          );
          pendingCapturer.completeWithPinnedIdentity();
          await capture;
          await pumpEventQueue();

          // THEN - the frame lands under the session it was painted under
          final screenshots = recordingQueue.addedEvents
              .where((e) => e.type == EventType.screenshot)
              .toList();
          expect(screenshots.length, 1);
          expect(screenshots.single.sessionId, capturedSessionId);
        },
      );

      test(
        'should record the frame when recording stops during capture',
        () async {
          // GIVEN - a capture is in flight
          final coordinator = await startRecordingWithPendingCapture();
          final sessionId = sessionManager.getCurrentSession().id;
          final capture = coordinator.captureSnapshot(
            RenderRepaintBoundary(),
            boundaryElement: boundaryElement,
          );
          await pumpEventQueue();

          // WHEN - recording stops before it resolves
          coordinator.stopRecording();
          pendingCapturer.completeWithPinnedIdentity();
          await capture;
          await pumpEventQueue();

          // THEN - the frame painted before the stop still lands
          final events = await eventQueue.fetchBatch(
            sessionId: sessionId,
            distinctId: currentDistinctId,
            maxBytes: 100000,
            maxCount: 10,
          );
          expect(events.where((e) => e.type == EventType.screenshot).length, 1);
        },
      );

      test(
        'should pin metadata to the captured session when a cross-session frame lands after rotation',
        () async {
          // GIVEN - a capture is in flight
          final coordinator = await startRecordingWithPendingCapture();
          final capturedSessionId = sessionManager.getCurrentSession().id;
          final capture = coordinator.captureSnapshot(
            RenderRepaintBoundary(),
            boundaryElement: boundaryElement,
          );
          await pumpEventQueue();

          // WHEN - the session rotates before the frame resolves
          coordinator.stopRecording();
          coordinator.startRecording(sessionsPercent: 100.0);
          await pumpEventQueue();
          final newSessionId = sessionManager.getCurrentSession().id;
          expect(newSessionId, isNot(equals(capturedSessionId)));
          pendingCapturer.completeWithPinnedIdentity();
          await capture;
          await pumpEventQueue();

          // THEN - the metadata sizing the frame lands in the same session as
          // the frame, so the captured replay is not left without dimensions
          final metadata = recordingQueue.addedEvents
              .where((e) => e.type == EventType.metadata)
              .toList();
          expect(metadata.length, 1);
          expect(metadata.single.sessionId, capturedSessionId);
          expect(metadata.single.sessionId, isNot(equals(newSessionId)));
        },
      );

      test(
        'should not throw when a frame resolves after the coordinator is disposed',
        () async {
          // GIVEN - a capture is in flight
          final coordinator = await startRecordingWithPendingCapture();
          final capture = coordinator.captureSnapshot(
            RenderRepaintBoundary(),
            boundaryElement: boundaryElement,
          );
          await pumpEventQueue();

          // WHEN - the coordinator is disposed before it resolves
          await coordinator.dispose();
          pendingCapturer.completeWithPinnedIdentity();
          await capture;
          await pumpEventQueue();

          // THEN - the frame still reaches the recorder, but the closed queue
          // rejects the write and the recorder swallows it
          expect(recordingQueue.isDisposed, isTrue);
          expect(recordingQueue.addedEvents, isNotEmpty);
          expect(recordingQueue.eventCount, 0);
        },
      );

      test(
        'should not touch the mask overlay when a frame resolves after the coordinator is disposed',
        () async {
          // GIVEN - the debug overlay is on and a capture is in flight
          final coordinator = createCoordinator(
            debugOptions: const DebugOptions(),
          );
          coordinator.startRecording(sessionsPercent: 100.0);
          await pumpEventQueue();
          final capture = coordinator.captureSnapshot(
            RenderRepaintBoundary(),
            boundaryElement: boundaryElement,
          );
          await pumpEventQueue();

          // WHEN - the coordinator is disposed, then the frame resolves with
          // regions that differ from the notifier's current value
          await coordinator.dispose();
          pendingCapturer.completeWithPinnedIdentity(
            maskRegions: [
              MaskRegionInfo(
                const Rect.fromLTWH(0, 0, 10, 10),
                MaskSource.auto,
              ),
            ],
          );

          // THEN - the disposed notifier is left alone rather than asserting
          await expectLater(capture, completes);
          await pumpEventQueue();
        },
      );

      test(
        'should record the frame under the captured distinct ID when identify runs during capture',
        () async {
          // GIVEN - a capture is in flight
          final coordinator = await startRecordingWithPendingCapture();
          final sessionId = sessionManager.getCurrentSession().id;
          final capture = coordinator.captureSnapshot(
            RenderRepaintBoundary(),
            boundaryElement: boundaryElement,
          );
          await pumpEventQueue();

          // WHEN - identify() swaps the distinct ID with recording still active
          currentDistinctId = 'user-2';
          pendingCapturer.completeWithPinnedIdentity();
          await capture;
          await pumpEventQueue();

          // THEN - the frame keeps the distinct ID it was captured under
          final events = await eventQueue.fetchBatch(
            sessionId: sessionId,
            distinctId: 'user-1',
            maxBytes: 100000,
            maxCount: 10,
          );
          expect(events.where((e) => e.type == EventType.screenshot).length, 1);
          expect(events.every((e) => e.distinctId == 'user-1'), isTrue);
        },
      );

      test(
        'should record the wireframe under the captured identity when identify runs during capture',
        () async {
          // GIVEN - a capture with a wireframe is in flight
          final coordinator = await startRecordingWithPendingCapture();
          final sessionId = sessionManager.getCurrentSession().id;
          final capture = coordinator.captureSnapshot(
            RenderRepaintBoundary(),
            boundaryElement: boundaryElement,
          );
          await pumpEventQueue();

          // WHEN - identify() swaps the distinct ID before capture completes
          currentDistinctId = 'user-2';
          pendingCapturer.completeWithPinnedIdentity(
            wireframes: WireframePayload(
              viewportWidth: 100,
              viewportHeight: 200,
              elements: const [],
            ),
          );
          await capture;
          await pumpEventQueue();

          // THEN - both visual events keep the identity pinned at capture time
          final visualEvents = recordingQueue.addedEvents
              .where(
                (event) =>
                    event.type == EventType.screenshot ||
                    event.type == EventType.wireframe,
              )
              .toList();
          expect(visualEvents, hasLength(2));
          expect(visualEvents.every((e) => e.sessionId == sessionId), isTrue);
          expect(visualEvents.every((e) => e.distinctId == 'user-1'), isTrue);
        },
      );

      test('should record the frame when identity is unchanged', () async {
        // GIVEN - a capture is in flight
        final coordinator = await startRecordingWithPendingCapture();
        final sessionId = sessionManager.getCurrentSession().id;
        final capture = coordinator.captureSnapshot(
          RenderRepaintBoundary(),
          boundaryElement: boundaryElement,
        );
        await pumpEventQueue();

        // WHEN - it resolves with session and distinct ID untouched
        pendingCapturer.completeWithPinnedIdentity();
        await capture;
        await pumpEventQueue();

        // THEN
        final events = await eventQueue.fetchBatch(
          sessionId: sessionId,
          distinctId: currentDistinctId,
          maxBytes: 100000,
          maxCount: 10,
        );
        final screenshots = events
            .where((e) => e.type == EventType.screenshot)
            .toList();
        expect(screenshots.length, 1);
      });
    });

    group('capture identity across the metadata await', () {
      late _PendingScreenshotCapturer pendingCapturer;
      late _PausingMetadataEventQueue pausingQueue;
      late Element boundaryElement;

      setUp(() async {
        pausingQueue = _PausingMetadataEventQueue();
        await pausingQueue.initialize();
        eventQueue = pausingQueue;
        eventRecorder = EventRecorder(
          eventQueue: pausingQueue,
          sessionManager: sessionManager,
          getDistinctId: () => currentDistinctId,
          logger: logger,
        );
        pendingCapturer = _PendingScreenshotCapturer(logger: logger);
        screenshotCapturer = pendingCapturer;
        boundaryElement = const SizedBox().createElement();
      });

      test(
        'should attribute the frame to the captured distinct ID when identify runs during the metadata await',
        () async {
          // GIVEN - a capture has resolved and its metadata write is pending
          final coordinator = createCoordinator();
          coordinator.startRecording(sessionsPercent: 100.0);
          await pumpEventQueue();
          final sessionId = sessionManager.getCurrentSession().id;

          final capture = coordinator.captureSnapshot(
            RenderRepaintBoundary(),
            boundaryElement: boundaryElement,
          );
          await pumpEventQueue();
          pendingCapturer.completeWithPinnedIdentity();
          await pumpEventQueue();
          expect(pausingQueue.metadataAddStarted, isTrue);

          // WHEN - identify() lands while metadata persistence is still blocked
          currentDistinctId = 'user-2';
          pausingQueue.releaseMetadata();
          await capture;
          await pumpEventQueue();

          // THEN - both events stay under the identity pinned at capture time
          expect(pausingQueue.eventCount, 2);
          final events = await pausingQueue.fetchBatch(
            sessionId: sessionId,
            distinctId: 'user-1',
            maxBytes: 100000,
            maxCount: 10,
          );
          expect(events.where((e) => e.type == EventType.screenshot).length, 1);
          expect(events.every((e) => e.distinctId == 'user-1'), isTrue);
        },
      );
    });
  });
}

/// Screenshot capturer whose capture resolves only when the test completes
/// [pendingCapture], holding a frame in flight across identity changes.
/// Pins the identity when capture starts, as the real capturer does at the frame.
class _PendingScreenshotCapturer extends ScreenshotCapturer {
  _PendingScreenshotCapturer({required super.logger})
    : super(
        directive: MaskingDirective(autoMaskTypes: {}),
        debugOverlayEnabled: false,
        compressor: DartPngCompressor(),
      );

  final Completer<CaptureResult> pendingCapture = Completer<CaptureResult>();
  late String pinnedSessionId;
  late String pinnedDistinctId;

  @override
  Future<CaptureResult> capture(
    RenderRepaintBoundary boundary, {
    required Session Function() getCurrentSession,
    required String Function() getDistinctId,
    required Element boundaryElement,
    Set<AutoMaskedView>? maskTypes,
  }) {
    pinnedSessionId = getCurrentSession().id;
    pinnedDistinctId = getDistinctId();
    return pendingCapture.future;
  }

  /// Resolve the in-flight capture with the identity pinned when it started.
  void completeWithPinnedIdentity({
    List<MaskRegionInfo> maskRegions = const [],
    WireframePayload? wireframes,
  }) => pendingCapture.complete(
    CaptureSuccess(
      data: Uint8List.fromList([1, 2, 3]),
      width: 100,
      height: 200,
      maskCount: maskRegions.length,
      timestamp: DateTime.now(),
      sessionId: pinnedSessionId,
      distinctId: pinnedDistinctId,
      maskRegions: maskRegions,
      wireframes: wireframes,
    ),
  );
}

/// Event queue that records every add attempt, including ones that throw
/// because the queue is disposed and would be swallowed by the recorder.
class _RecordingEventQueue extends InMemoryEventQueue {
  final List<SessionReplayEvent> addedEvents = [];

  @override
  Future<void> add(SessionReplayEvent event) async {
    addedEvents.add(event);
    await super.add(event);
  }
}

/// Event queue that blocks metadata writes until [releaseMetadata], holding the
/// recorder inside its metadata await while a test changes the current identity.
class _PausingMetadataEventQueue extends InMemoryEventQueue {
  final Completer<void> _metadataGate = Completer<void>();
  bool metadataAddStarted = false;

  @override
  Future<void> add(SessionReplayEvent event) async {
    if (event.type == EventType.metadata) {
      metadataAddStarted = true;
      await _metadataGate.future;
    }
    await super.add(event);
  }

  void releaseMetadata() {
    if (!_metadataGate.isCompleted) _metadataGate.complete();
  }
}

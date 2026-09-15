import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session_replay_coordinator.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/event_recorder.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/screenshot_capturer.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/native_image_compressor.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/upload/upload_service.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/settings/settings_service.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/settings/settings_storage_provider.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/upload/payload_serializer.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session/session_manager.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session/idle_timeout_timer.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';
import 'package:mixpanel_flutter_session_replay/src/models/results.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_http_client.dart';
import 'helpers/in_memory_event_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionReplayCoordinator - Web Session Features', () {
    late InMemoryEventQueue eventQueue;
    late SessionManager sessionManager;
    late EventRecorder eventRecorder;
    late UploadService uploadService;
    late SettingsService settingsService;
    late ScreenshotCapturer screenshotCapturer;
    late MixpanelLogger logger;

    SessionReplayCoordinator createCoordinator({
      double autoRecordSessionsPercent = 0,
      IdleTimeoutTimer? idleTimer,
      Duration? maxSessionDuration,
      Future<void> Function(String, int, int)? persistIdleExpiry,
    }) {
      return SessionReplayCoordinator(
        screenshotCapturer: screenshotCapturer,
        eventRecorder: eventRecorder,
        uploadService: uploadService,
        settingsService: settingsService,
        sessionManager: sessionManager,
        logger: logger,
        autoRecordSessionsPercent: autoRecordSessionsPercent,
        remoteSettingsMode: RemoteSettingsMode.disabled,
        debugOptions: null,
        idleTimer: idleTimer,
        maxSessionDuration: maxSessionDuration,
        persistIdleExpiry: persistIdleExpiry,
      );
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.mixpanel.flutter_session_replay'),
            (call) async => null,
          );

      logger = MixpanelLogger(LogLevel.none);
      eventQueue = InMemoryEventQueue();
      await eventQueue.initialize();
      sessionManager = SessionManager();

      eventRecorder = EventRecorder(
        eventQueue: eventQueue,
        sessionManager: sessionManager,
        getDistinctId: () => 'user-1',
        logger: logger,
      );

      final httpClient = createFakeHttpClient(statusCode: 200);
      uploadService = UploadService(
        eventQueue: eventQueue,
        payloadSerializer: PayloadSerializer('test-token'),
        wifiOnly: false,
        getRemoteEnablementState: () => RemoteEnablementState.enabled,
        flushInterval: const Duration(hours: 1),
        logger: logger,
        httpClient: httpClient,
      );

      final storageProvider = SettingsStorageProvider(
        token: 'test-token',
        logger: logger,
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
      } catch (_) {}
    });

    group('resumeSession', () {
      test(
        'staged session waits for remote enablement before recording',
        () async {
          final session = Session(
            id: 'pending-session',
            startTime: DateTime.now().toUtc(),
            status: SessionStatus.active,
          );
          final coordinator = createCoordinator();

          coordinator.prepareSessionResume(session);

          expect(coordinator.recordingState, RecordingState.notRecording);
          expect(coordinator.replayId, isNull);

          coordinator.onAppForegrounded();
          await pumpEventQueue();

          expect(coordinator.recordingState, RecordingState.recording);
          expect(coordinator.replayId, 'pending-session');
        },
      );

      test('explicit stop cancels a staged session', () async {
        final session = Session(
          id: 'cancelled-session',
          startTime: DateTime.now().toUtc(),
          status: SessionStatus.active,
        );
        final coordinator = createCoordinator();
        coordinator.prepareSessionResume(session);

        coordinator.stopRecording();
        coordinator.onAppForegrounded();
        await pumpEventQueue();

        expect(coordinator.recordingState, RecordingState.notRecording);
        expect(coordinator.replayId, isNull);
      });

      test('sets recording state to recording', () {
        // GIVEN
        final session = Session(
          id: 'resumed-session',
          startTime: DateTime.utc(2025, 1, 1),
          status: SessionStatus.active,
        );
        final coordinator = createCoordinator();

        // WHEN
        coordinator.resumeSession(session);

        // THEN
        expect(coordinator.recordingState, RecordingState.recording);
      });

      test('sets replayId to the resumed session ID', () {
        // GIVEN
        final session = Session(
          id: 'my-replay-id',
          startTime: DateTime.utc(2025, 1, 1),
          status: SessionStatus.active,
        );
        final coordinator = createCoordinator();

        // WHEN
        coordinator.resumeSession(session);

        // THEN
        expect(coordinator.replayId, 'my-replay-id');
      });

      test('does not re-roll sampling', () {
        // GIVEN — 0% sampling would normally prevent recording
        final session = Session(
          id: 'forced-session',
          startTime: DateTime.utc(2025, 1, 1),
          status: SessionStatus.active,
        );
        final coordinator = createCoordinator(autoRecordSessionsPercent: 0);

        // WHEN — resume bypasses sampling
        coordinator.resumeSession(session);

        // THEN
        expect(coordinator.recordingState, RecordingState.recording);
      });

      test('is a no-op after dispose', () async {
        // GIVEN
        final session = Session(
          id: 'disposed-session',
          startTime: DateTime.utc(2025, 1, 1),
          status: SessionStatus.active,
        );
        final coordinator = createCoordinator();
        await coordinator.dispose();

        // WHEN
        coordinator.resumeSession(session);

        // THEN
        expect(coordinator.recordingState, RecordingState.notRecording);
      });
    });

    group('handleIdleTimeout', () {
      test('stops recording when idle timeout fires', () async {
        // GIVEN
        final coordinator = createCoordinator();
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();
        expect(coordinator.recordingState, RecordingState.recording);

        // WHEN
        coordinator.handleIdleTimeout();

        // THEN
        expect(coordinator.recordingState, RecordingState.notRecording);
      });

      test('is a no-op when not recording', () {
        // GIVEN
        final coordinator = createCoordinator();
        expect(coordinator.recordingState, RecordingState.notRecording);

        // WHEN
        coordinator.handleIdleTimeout();

        // THEN — no crash, still not recording
        expect(coordinator.recordingState, RecordingState.notRecording);
      });
    });

    group('onUserActivity', () {
      test('restarts recording after idle timeout', () async {
        // GIVEN
        final coordinator = createCoordinator(autoRecordSessionsPercent: 100.0);
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();
        coordinator.handleIdleTimeout();
        expect(coordinator.recordingState, RecordingState.notRecording);

        // WHEN
        coordinator.onUserActivity();
        await pumpEventQueue();

        // THEN
        expect(coordinator.recordingState, RecordingState.recording);
      });

      test('creates a new session after idle restart', () async {
        // GIVEN
        final coordinator = createCoordinator(autoRecordSessionsPercent: 100.0);
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();
        final originalReplayId = coordinator.replayId;
        coordinator.handleIdleTimeout();

        // WHEN
        coordinator.onUserActivity();
        await pumpEventQueue();

        // THEN — new session ID
        expect(coordinator.replayId, isNot(equals(originalReplayId)));
      });

      test('is a no-op when not idled out', () {
        // GIVEN — coordinator is not recording and not idled out
        final coordinator = createCoordinator();

        // WHEN
        coordinator.onUserActivity();

        // THEN — no crash, no state change
        expect(coordinator.recordingState, RecordingState.notRecording);
      });

      test('is a no-op during normal recording', () async {
        // GIVEN — coordinator is actively recording (not idled out)
        final coordinator = createCoordinator();
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();
        final currentReplayId = coordinator.replayId;

        // WHEN
        coordinator.onUserActivity();

        // THEN — same session, still recording
        expect(coordinator.recordingState, RecordingState.recording);
        expect(coordinator.replayId, currentReplayId);
      });
    });

    group('idle timer integration', () {
      test('coordinator accepts idle timer without error', () async {
        // GIVEN
        final idleTimer = IdleTimeoutTimer(
          timeout: const Duration(minutes: 30),
          onTimeout: () {},
        );

        // WHEN
        final coordinator = createCoordinator(idleTimer: idleTimer);
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();

        // THEN
        expect(coordinator.recordingState, RecordingState.recording);

        idleTimer.dispose();
      });

      test('coordinator accepts max session duration without error', () async {
        // GIVEN / WHEN
        final coordinator = createCoordinator(
          maxSessionDuration: const Duration(hours: 24),
        );
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();

        // THEN
        expect(coordinator.recordingState, RecordingState.recording);
      });
    });

    group('persistIdleExpiry callback', () {
      test('persist callback is invoked on activity', () async {
        // GIVEN
        final persistedCalls = <(String, int, int)>[];
        final idleTimer = IdleTimeoutTimer(
          timeout: const Duration(minutes: 30),
          onTimeout: () {},
        );
        final coordinator = createCoordinator(
          idleTimer: idleTimer,
          maxSessionDuration: const Duration(hours: 24),
          persistIdleExpiry: (sessionId, idleExpiresMs, maxExpiresMs) async {
            persistedCalls.add((sessionId, idleExpiresMs, maxExpiresMs));
          },
        );
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();

        // The initial persist is called on session start
        // (persistExpiryDebounced with null _lastExpiryWriteTime)
        expect(persistedCalls, isNotEmpty);
        final persisted = persistedCalls.single;
        expect(persisted.$3, greaterThan(persisted.$2));

        idleTimer.dispose();
      });
    });
  });
}

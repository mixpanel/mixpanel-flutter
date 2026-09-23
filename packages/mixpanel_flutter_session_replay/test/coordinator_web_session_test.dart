import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
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
      RemoteSettingsMode remoteSettingsMode = RemoteSettingsMode.disabled,
      IdleTimeoutTimer? idleTimer,
      Duration? maxSessionDuration,
      ReplayBackgroundBehavior backgroundBehavior =
          ReplayBackgroundBehavior.stop,
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
        remoteSettingsMode: remoteSettingsMode,
        debugOptions: null,
        idleTimer: idleTimer,
        maxSessionDuration: maxSessionDuration,
        backgroundBehavior: backgroundBehavior,
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
      test('remote web durations replace local limits', () async {
        // GIVEN remote values in milliseconds and different local limits
        settingsService = SettingsService(
          storageProvider: SettingsStorageProvider(
            token: 'test-token',
            logger: logger,
          ),
          token: 'test-token',
          logger: logger,
          httpClient: createFakeSettingsClient(
            isEnabled: true,
            sdkConfig: {
              'record_max_ms': 60000,
              'record_idle_timeout_ms': 10000,
            },
          ),
        );
        final deadlines = <(int, int)>[];
        final localIdleTimer = IdleTimeoutTimer(
          timeout: const Duration(minutes: 30),
          onTimeout: () {},
        );
        final coordinator = createCoordinator(
          autoRecordSessionsPercent: 100,
          remoteSettingsMode: RemoteSettingsMode.fallback,
          idleTimer: localIdleTimer,
          maxSessionDuration: const Duration(hours: 24),
          persistIdleExpiry: (_, idle, max) async {
            deadlines.add((idle, max));
          },
        );
        final now = DateTime.utc(2026, 1, 1);

        // WHEN remote settings arrive before recording starts
        await withClock(Clock.fixed(now), () async {
          coordinator.onAppForegrounded();
          await pumpEventQueue();
        });

        // THEN the persisted web deadlines use the remote values
        expect(coordinator.recordingState, RecordingState.recording);
        expect(deadlines.single.$1, now.millisecondsSinceEpoch + 10000);
        expect(deadlines.single.$2, now.millisecondsSinceEpoch + 60000);

        // A frozen page still uses the remote idle deadline when foregrounded.
        final firstReplayId = coordinator.replayId;
        await withClock(
          Clock.fixed(now.add(const Duration(seconds: 11))),
          () async {
            coordinator.onAppForegrounded();
            await pumpEventQueue();
          },
        );
        expect(coordinator.replayId, isNot(firstReplayId));
      });

      test(
        'remote idle timeout works when local idle timeout is disabled',
        () async {
          // GIVEN no local idle timer, but a remote timeout
          settingsService = SettingsService(
            storageProvider: SettingsStorageProvider(
              token: 'test-token',
              logger: logger,
            ),
            token: 'test-token',
            logger: logger,
            httpClient: createFakeSettingsClient(
              isEnabled: true,
              sdkConfig: {'record_idle_timeout_ms': 5000},
            ),
          );
          final deadlines = <(int, int)>[];
          final coordinator = createCoordinator(
            autoRecordSessionsPercent: 100,
            remoteSettingsMode: RemoteSettingsMode.fallback,
            maxSessionDuration: const Duration(hours: 24),
            persistIdleExpiry: (_, idle, max) async {
              deadlines.add((idle, max));
            },
          );
          final now = DateTime.utc(2026, 1, 1);

          // WHEN
          await withClock(Clock.fixed(now), () async {
            coordinator.onAppForegrounded();
            await pumpEventQueue();
          });

          // THEN remote settings create an active idle timer
          expect(deadlines.single.$1, now.millisecondsSinceEpoch + 5000);
        },
      );

      test('disabled remote mode keeps local web durations', () async {
        // GIVEN remote limits are present but remote config is disabled
        settingsService = SettingsService(
          storageProvider: SettingsStorageProvider(
            token: 'test-token',
            logger: logger,
          ),
          token: 'test-token',
          logger: logger,
          httpClient: createFakeSettingsClient(
            isEnabled: true,
            sdkConfig: {
              'record_max_ms': 60000,
              'record_idle_timeout_ms': 10000,
            },
          ),
        );
        final deadlines = <(int, int)>[];
        final idleTimer = IdleTimeoutTimer(
          timeout: const Duration(minutes: 30),
          onTimeout: () {},
        );
        final coordinator = createCoordinator(
          autoRecordSessionsPercent: 100,
          idleTimer: idleTimer,
          maxSessionDuration: const Duration(hours: 24),
          persistIdleExpiry: (_, idle, max) async {
            deadlines.add((idle, max));
          },
        );
        final now = DateTime.utc(2026, 1, 1);

        // WHEN
        await withClock(Clock.fixed(now), () async {
          coordinator.onAppForegrounded();
          await pumpEventQueue();
        });

        // THEN the app-provided limits remain in effect
        expect(
          deadlines.single.$1,
          now.millisecondsSinceEpoch +
              const Duration(minutes: 30).inMilliseconds,
        );
        expect(
          deadlines.single.$2,
          now.millisecondsSinceEpoch + const Duration(hours: 24).inMilliseconds,
        );
      });

      test(
        'remote web durations do not create native session timers',
        () async {
          // GIVEN a native-shaped coordinator with no web duration
          settingsService = SettingsService(
            storageProvider: SettingsStorageProvider(
              token: 'test-token',
              logger: logger,
            ),
            token: 'test-token',
            logger: logger,
            httpClient: createFakeSettingsClient(
              isEnabled: true,
              sdkConfig: {
                'record_max_ms': 60000,
                'record_idle_timeout_ms': 10000,
              },
            ),
          );
          final coordinator = createCoordinator(
            autoRecordSessionsPercent: 100,
            remoteSettingsMode: RemoteSettingsMode.fallback,
          );

          // WHEN
          coordinator.onAppForegrounded();
          await pumpEventQueue();

          // THEN
          expect(coordinator.recordingState, RecordingState.recording);
          expect(coordinator.hasMaxSessionTimerForTest, false);
        },
      );

      test(
        'remote max duration rejects a stale persisted web session',
        () async {
          // GIVEN a session still valid under the local 24-hour cap
          settingsService = SettingsService(
            storageProvider: SettingsStorageProvider(
              token: 'test-token',
              logger: logger,
            ),
            token: 'test-token',
            logger: logger,
            httpClient: createFakeSettingsClient(
              isEnabled: true,
              sdkConfig: {'record_max_ms': 600000},
            ),
          );
          final coordinator = createCoordinator(
            autoRecordSessionsPercent: 100,
            remoteSettingsMode: RemoteSettingsMode.fallback,
            maxSessionDuration: const Duration(hours: 24),
          );
          final now = DateTime.utc(2026, 1, 1, 12);
          final stale = Session(
            id: 'stale-web-session',
            startTime: now.subtract(const Duration(minutes: 30)),
            status: SessionStatus.active,
          );

          // WHEN the remote 10-minute cap arrives before resumption
          await withClock(Clock.fixed(now), () async {
            coordinator.prepareSessionResume(stale);
            coordinator.onAppForegrounded();
            await pumpEventQueue();
          });

          // THEN a new replay starts instead of reviving the stale one
          expect(coordinator.recordingState, RecordingState.recording);
          expect(coordinator.replayId, isNot('stale-web-session'));
        },
      );

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

    group('PR #283 review findings', () {
      test(
        'resuming a persisted session keeps its remaining idle window',
        () async {
          // GIVEN a persisted session whose 30 minute idle deadline is 2
          // minutes away
          final idleTimer = IdleTimeoutTimer(
            timeout: const Duration(minutes: 30),
            onTimeout: () {},
          );
          addTearDown(idleTimer.dispose);
          final coordinator = createCoordinator(
            autoRecordSessionsPercent: 100,
            backgroundBehavior: const ReplayBackgroundBehavior.pause(
              idleTimeout: Duration(minutes: 30),
            ),
            idleTimer: idleTimer,
          );
          final now = DateTime.utc(2026, 1, 1, 12);
          final storedDeadline = now.add(const Duration(minutes: 2));
          final session = Session(
            id: 'resumed-with-deadline',
            startTime: now.subtract(const Duration(minutes: 28)),
            status: SessionStatus.active,
          );

          // WHEN it resumes, then goes away for 5 minutes
          await withClock(Clock.fixed(now), () async {
            coordinator.prepareSessionResume(
              session,
              idleExpiry: storedDeadline,
            );
            coordinator.onAppForegrounded();
            await pumpEventQueue();
            expect(coordinator.replayId, 'resumed-with-deadline');
            coordinator.onAppBackgrounded();
            await pumpEventQueue();
          });
          await withClock(
            Clock.fixed(now.add(const Duration(minutes: 5))),
            () async {
              coordinator.onAppForegrounded();
              await pumpEventQueue();
            },
          );

          // THEN the stored deadline governed: 5 minutes is past it, so the
          // session is replaced. Re-arming for a fresh 30 minutes would have
          // kept it alive.
          expect(coordinator.replayId, isNot('resumed-with-deadline'));
        },
      );

      test(
        'resuming without a stored deadline falls back to a full window',
        () async {
          // GIVEN a resume that carries no persisted deadline
          final idleTimer = IdleTimeoutTimer(
            timeout: const Duration(minutes: 30),
            onTimeout: () {},
          );
          addTearDown(idleTimer.dispose);
          final coordinator = createCoordinator(
            autoRecordSessionsPercent: 100,
            backgroundBehavior: const ReplayBackgroundBehavior.pause(
              idleTimeout: Duration(minutes: 30),
            ),
            idleTimer: idleTimer,
          );
          final now = DateTime.utc(2026, 1, 1, 12);
          final session = Session(
            id: 'resumed-no-deadline',
            startTime: now,
            status: SessionStatus.active,
          );

          // WHEN it resumes and returns 5 minutes later
          await withClock(Clock.fixed(now), () async {
            coordinator.prepareSessionResume(session);
            coordinator.onAppForegrounded();
            await pumpEventQueue();
            coordinator.onAppBackgrounded();
            await pumpEventQueue();
          });
          await withClock(
            Clock.fixed(now.add(const Duration(minutes: 5))),
            () async {
              coordinator.onAppForegrounded();
              await pumpEventQueue();
            },
          );

          // THEN it is still within a full 30 minute window
          expect(coordinator.replayId, 'resumed-no-deadline');
        },
      );

      test(
        'max duration ends a static session with the idle timeout disabled',
        () async {
          // GIVEN recording with no idle timer at all (idleTimeout: 0) and a
          // 1 minute cap -- nothing captures, nothing interacts, and the app
          // never leaves the foreground
          final coordinator = createCoordinator(
            autoRecordSessionsPercent: 100,
            backgroundBehavior: const ReplayBackgroundBehavior.pause(
              idleTimeout: Duration(minutes: 30),
            ),
            maxSessionDuration: const Duration(minutes: 1),
          );
          coordinator.startRecording(sessionsPercent: 100);
          await pumpEventQueue();
          expect(coordinator.recordingState, RecordingState.recording);

          // WHEN the cap elapses with no activity of any kind
          await Future<void>.delayed(const Duration(milliseconds: 20));

          // THEN a timer is armed to end it, rather than the session waiting
          // for a capture that will never come
          expect(
            coordinator.hasMaxSessionTimerForTest,
            isTrue,
            reason:
                'max duration must be enforced by a timer, not only on '
                'the capture and interaction paths',
          );
        },
      );

      test('max duration expires at the exact deadline', () {
        fakeAsync((async) {
          // GIVEN a static recording with a one-minute maximum duration
          final coordinator = createCoordinator(
            autoRecordSessionsPercent: 100,
            maxSessionDuration: const Duration(minutes: 1),
          );
          coordinator.startRecording(sessionsPercent: 100);
          async.flushMicrotasks();
          expect(coordinator.recordingState, RecordingState.recording);

          // WHEN the one-shot timer observes exactly the expiry instant
          async.elapse(const Duration(minutes: 1));

          // THEN equality counts as expired and the recording is stopped
          expect(coordinator.recordingState, RecordingState.notRecording);
        });
      });
    });

    group('background/foreground continuity', () {
      /// Records super-property traffic on whichever channel
      /// [SessionReplaySender] picks for the host platform.
      List<String> recordSenderCalls() {
        final calls = <String>[];
        for (final channel in const [
          MethodChannel('mixpanel_flutter'),
          MethodChannel('com.mixpanel.flutter_session_replay'),
        ]) {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, (call) async {
                calls.add(call.method);
                return null;
              });
          addTearDown(
            () => TestDefaultBinaryMessengerBinding
                .instance
                .defaultBinaryMessenger
                .setMockMethodCallHandler(channel, null),
          );
        }
        return calls;
      }

      test('web pauses recording while hidden', () async {
        // GIVEN a web coordinator recording a session
        final coordinator = createCoordinator(
          autoRecordSessionsPercent: 100,
          backgroundBehavior: const ReplayBackgroundBehavior.pause(
            idleTimeout: Duration(minutes: 30),
          ),
        );
        coordinator.startRecording(sessionsPercent: 100);
        await pumpEventQueue();
        final replayId = coordinator.replayId;
        expect(replayId, isNotNull);

        // WHEN the tab is hidden
        coordinator.onAppBackgrounded();
        await pumpEventQueue();

        // THEN capture pauses without ending the replay
        expect(coordinator.recordingState, RecordingState.paused);
        expect(coordinator.replayId, isNull);
      });

      test('web keeps the same session after the tab is shown again', () async {
        // GIVEN a web coordinator recording a session
        final coordinator = createCoordinator(
          autoRecordSessionsPercent: 100,
          backgroundBehavior: const ReplayBackgroundBehavior.pause(
            idleTimeout: Duration(minutes: 30),
          ),
        );
        coordinator.startRecording(sessionsPercent: 100);
        await pumpEventQueue();
        final replayId = coordinator.replayId;

        // WHEN it is hidden and shown again
        coordinator.onAppBackgrounded();
        await pumpEventQueue();
        coordinator.onAppForegrounded();
        await pumpEventQueue();

        // THEN it is one continuous replay, not a new one
        expect(coordinator.recordingState, RecordingState.recording);
        expect(coordinator.replayId, replayId);
      });

      test('pause idle timeout replaces the session on return', () async {
        final coordinator = createCoordinator(
          autoRecordSessionsPercent: 100,
          backgroundBehavior: const ReplayBackgroundBehavior.pause(
            idleTimeout: Duration(minutes: 5),
          ),
        );
        final backgroundedAt = DateTime.utc(2026, 1, 1, 12);
        String? replayId;
        await withClock(Clock.fixed(backgroundedAt), () async {
          coordinator.startRecording(sessionsPercent: 100);
          await pumpEventQueue();
          replayId = coordinator.replayId;
          coordinator.onAppBackgrounded();
          await pumpEventQueue();
        });

        await withClock(
          Clock.fixed(backgroundedAt.add(const Duration(minutes: 6))),
          () async {
            coordinator.onAppForegrounded();
            await pumpEventQueue();
          },
        );

        expect(coordinator.recordingState, RecordingState.recording);
        expect(coordinator.replayId, isNot(replayId));
      });

      test(
        'web keeps an explicitly started recording alive while hidden',
        () async {
          // GIVEN recording started explicitly while auto-recording is disabled
          final coordinator = createCoordinator(
            autoRecordSessionsPercent: 0,
            backgroundBehavior: const ReplayBackgroundBehavior.pause(
              idleTimeout: Duration(minutes: 30),
            ),
          );
          coordinator.startRecording(sessionsPercent: 100);
          await pumpEventQueue();
          final replayId = coordinator.replayId;

          // WHEN hidden and shown again
          coordinator.onAppBackgrounded();
          await pumpEventQueue();
          coordinator.onAppForegrounded();
          await pumpEventQueue();

          // THEN it survives, though a 0% roll would never have restarted it
          expect(coordinator.recordingState, RecordingState.recording);
          expect(coordinator.replayId, replayId);
        },
      );

      test('web unregisters \$mp_replay_id while hidden', () async {
        // GIVEN a recording web session, with sender traffic captured
        final calls = recordSenderCalls();
        final coordinator = createCoordinator(
          autoRecordSessionsPercent: 100,
          backgroundBehavior: const ReplayBackgroundBehavior.pause(
            idleTimeout: Duration(minutes: 30),
          ),
        );
        coordinator.startRecording(sessionsPercent: 100);
        await pumpEventQueue();
        expect(
          calls,
          contains('registerSuperProperties'),
          reason:
              'sanity: the register call must be observable for the '
              'absence of an unregister below to mean anything',
        );

        // WHEN the tab is hidden
        coordinator.onAppBackgrounded();
        await pumpEventQueue();

        // THEN analytics events emitted while hidden are not associated with
        // a replay interval that has no captured frames.
        expect(calls, contains('unregisterSuperProperty'));
      });

      test('native ends the session on background', () async {
        // GIVEN a native coordinator (stop is the default)
        final coordinator = createCoordinator(autoRecordSessionsPercent: 0);
        coordinator.startRecording(sessionsPercent: 100);
        await pumpEventQueue();

        // WHEN backgrounded and foregrounded
        coordinator.onAppBackgrounded();
        await pumpEventQueue();
        expect(coordinator.recordingState, RecordingState.notRecording);
        coordinator.onAppForegrounded();
        await pumpEventQueue();

        // THEN nothing resumes, matching mixpanel-android/ios
        expect(coordinator.recordingState, RecordingState.notRecording);
      });

      test(
        'an idle timeout that fires while hidden ends the session',
        () async {
          // GIVEN a web session hidden with its idle timer still running
          final coordinator = createCoordinator(
            autoRecordSessionsPercent: 100,
            backgroundBehavior: const ReplayBackgroundBehavior.pause(
              idleTimeout: Duration(minutes: 30),
            ),
          );
          coordinator.startRecording(sessionsPercent: 100);
          await pumpEventQueue();
          final replayId = coordinator.replayId;
          coordinator.onAppBackgrounded();
          await pumpEventQueue();

          // WHEN the idle timeout elapses while the tab is away
          coordinator.handleIdleTimeout();
          expect(coordinator.recordingState, RecordingState.notRecording);

          // THEN returning starts a fresh session rather than continuing
          coordinator.onAppForegrounded();
          await pumpEventQueue();
          expect(coordinator.recordingState, RecordingState.recording);
          expect(coordinator.replayId, isNot(replayId));
        },
      );

      test('a session past its max duration is replaced on return', () async {
        // GIVEN a web session recording under a 24h cap
        final coordinator = createCoordinator(
          autoRecordSessionsPercent: 100,
          backgroundBehavior: const ReplayBackgroundBehavior.pause(
            idleTimeout: Duration(minutes: 30),
          ),
          maxSessionDuration: const Duration(hours: 24),
        );
        final startedAt = DateTime.utc(2026, 1, 1, 12);
        String? replayId;
        await withClock(Clock.fixed(startedAt), () async {
          coordinator.startRecording(sessionsPercent: 100);
          await pumpEventQueue();
          replayId = coordinator.replayId;
          coordinator.onAppBackgrounded();
          await pumpEventQueue();
        });

        // WHEN the tab comes back beyond the cap
        await withClock(
          Clock.fixed(startedAt.add(const Duration(hours: 25))),
          () async {
            coordinator.onAppForegrounded();
            await pumpEventQueue();
          },
        );

        // THEN the capped session is replaced, not silently extended
        expect(coordinator.replayId, isNot(replayId));
      });

      test(
        'a frozen page whose idle window elapsed does not keep recording',
        () async {
          // GIVEN a web session hidden with a 30 minute idle window.
          // The idle Timer is deliberately never fired: this models bfcache
          // or OS suspension, where the page is frozen and timers do not
          // advance even though wall-clock time passes.
          final idleTimer = IdleTimeoutTimer(
            timeout: const Duration(minutes: 30),
            onTimeout: () {},
          );
          addTearDown(idleTimer.dispose);
          final coordinator = createCoordinator(
            autoRecordSessionsPercent: 100,
            backgroundBehavior: const ReplayBackgroundBehavior.pause(
              idleTimeout: Duration(minutes: 30),
            ),
            idleTimer: idleTimer,
          );
          final hiddenAt = DateTime.utc(2026, 1, 1, 12);
          String? replayId;
          await withClock(Clock.fixed(hiddenAt), () async {
            coordinator.startRecording(sessionsPercent: 100);
            await pumpEventQueue();
            replayId = coordinator.replayId;
            coordinator.onAppBackgrounded();
            await pumpEventQueue();
            // Paused, but the replay session is still retained.
            expect(coordinator.recordingState, RecordingState.paused);
          });

          // WHEN the page is restored 45 minutes later
          await withClock(
            Clock.fixed(hiddenAt.add(const Duration(minutes: 45))),
            () async {
              coordinator.onAppForegrounded();
              await pumpEventQueue();
            },
          );

          // THEN the stale session is not carried on, even though the timer
          // never fired
          expect(coordinator.replayId, isNot(replayId));
        },
      );

      test(
        'a frozen page within its idle window keeps the same session',
        () async {
          // GIVEN the same setup, restored before the window elapses
          final idleTimer = IdleTimeoutTimer(
            timeout: const Duration(minutes: 30),
            onTimeout: () {},
          );
          addTearDown(idleTimer.dispose);
          final coordinator = createCoordinator(
            autoRecordSessionsPercent: 100,
            backgroundBehavior: const ReplayBackgroundBehavior.pause(
              idleTimeout: Duration(minutes: 30),
            ),
            idleTimer: idleTimer,
          );
          final hiddenAt = DateTime.utc(2026, 1, 1, 12);
          String? replayId;
          await withClock(Clock.fixed(hiddenAt), () async {
            coordinator.startRecording(sessionsPercent: 100);
            await pumpEventQueue();
            replayId = coordinator.replayId;
            coordinator.onAppBackgrounded();
            await pumpEventQueue();
          });

          // WHEN restored after 10 minutes
          await withClock(
            Clock.fixed(hiddenAt.add(const Duration(minutes: 10))),
            () async {
              coordinator.onAppForegrounded();
              await pumpEventQueue();
            },
          );

          // THEN it is still one continuous replay
          expect(coordinator.recordingState, RecordingState.recording);
          expect(coordinator.replayId, replayId);
        },
      );

      test('an explicit stop while hidden stays stopped on return', () async {
        // GIVEN a hidden web session
        final coordinator = createCoordinator(
          autoRecordSessionsPercent: 0,
          backgroundBehavior: const ReplayBackgroundBehavior.pause(
            idleTimeout: Duration(minutes: 30),
          ),
        );
        coordinator.startRecording(sessionsPercent: 100);
        await pumpEventQueue();
        coordinator.onAppBackgrounded();
        await pumpEventQueue();

        // WHEN the host explicitly stops recording before returning
        coordinator.stopRecording();
        coordinator.onAppForegrounded();
        await pumpEventQueue();

        // THEN the explicit stop wins
        expect(coordinator.recordingState, RecordingState.notRecording);
      });
    });
  });
}

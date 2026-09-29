import 'package:mixpanel_flutter_session_replay/src/internal/session/recording_limits.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session/resumable_session.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session/session_persistence.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/capture/to_image_frame_acquirer.dart';
import 'dart:async';
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
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
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';
import 'package:mixpanel_flutter_session_replay/src/models/results.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session_event.dart';
import 'package:mixpanel_flutter_session_replay/src/widgets/interaction_detector.dart';

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

    /// Persistence of the most recently created coordinator.
    late StoredSessionPersistence persistence;

    /// Offers [session] to the most recently created coordinator for resume,
    /// as platform init does for a replay a previous page load left behind.
    void stageResume(
      Session session, {
      DateTime? idleExpiry,
      DateTime? backgroundExpiry,
    }) => persistence.stageResume(
      ResumableSession(
        session,
        idleExpiry: idleExpiry,
        backgroundExpiry: backgroundExpiry,
      ),
    );

    SessionReplayCoordinator createCoordinator({
      double autoRecordSessionsPercent = 0,
      RemoteSettingsMode remoteSettingsMode = RemoteSettingsMode.disabled,
      Duration? idleTimeout,
      Duration? maxSessionDuration,
      ReplayBackgroundBehavior? backgroundBehavior =
          ReplayBackgroundBehavior.stop,
      Future<void> Function(String, int, int, int?)? persistIdleExpiry,
      EventRecorder? recorder,
      ScreenshotCapturer? capturer,
    }) {
      persistence = StoredSessionPersistence(
        write: persistIdleExpiry ?? (_, _, _, _) async {},
        logger: logger,
      );
      return SessionReplayCoordinator(
        screenshotCapturer: capturer ?? screenshotCapturer,
        eventRecorder: recorder ?? eventRecorder,
        uploadService: uploadService,
        settingsService: settingsService,
        sessionManager: sessionManager,
        logger: logger,
        autoRecordSessionsPercent: autoRecordSessionsPercent,
        remoteSettingsMode: remoteSettingsMode,
        debugOptions: null,
        durationLimits: maxSessionDuration == null && idleTimeout == null
            ? null
            : RecordingDurationLimits(
                maximum: maxSessionDuration ?? maxRecordingDuration,
                idle: idleTimeout,
              ),
        backgroundBehavior: backgroundBehavior,
        sessionPersistence: persistence,
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
        frameAcquirer: ToImageFrameAcquirer(
          DartPngCompressor(),
          logger: MixpanelLogger(LogLevel.none),
        ),
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

    test(
      'should not activate recording when metadata finishes after maximum expiry',
      () {
        fakeAsync((async) {
          // GIVEN metadata persistence outlasting a short web recording limit.
          final delayedQueue = _DelayedMetadataQueue();
          eventRecorder = EventRecorder(
            eventQueue: delayedQueue,
            sessionManager: sessionManager,
            getDistinctId: () => 'user-1',
            logger: logger,
          );
          final coordinator = createCoordinator(
            maxSessionDuration: const Duration(seconds: 1),
          );
          coordinator.startRecording();
          expect(coordinator.recordingState, RecordingState.initializing);

          // WHEN the maximum expires before storage acknowledges the session.
          async.elapse(const Duration(seconds: 2));
          delayedQueue.ready.complete();
          async.flushMicrotasks();

          // THEN the completion cannot revive the expired recording.
          expect(coordinator.recordingState, RecordingState.notRecording);
          expect(coordinator.replayId, isNull);
          expect(coordinator.hasMaxSessionTimerForTest, isFalse);
          coordinator.dispose();
          async.flushMicrotasks();
        });
      },
    );

    group('resume and stop regressions', () {
      for (final remaining in [Duration.zero, const Duration(seconds: -1)]) {
        test(
          'rejects a staged background deadline with $remaining remaining',
          () async {
            // GIVEN a reload staged before settings / foreground resolution.
            final now = DateTime.utc(2026, 9, 28, 12);
            final coordinator = createCoordinator(
              autoRecordSessionsPercent: 100,
            );
            addTearDown(coordinator.dispose);
            stageResume(
              Session(
                id: 'paused-reload',
                startTime: now,
                status: SessionStatus.active,
              ),
              backgroundExpiry: now.add(remaining),
            );

            // WHEN the page can finally start recording.
            await withClock(Clock.fixed(now), () async {
              coordinator.onAppForegrounded();
              await pumpEventQueue();
            });

            // THEN expired background retention causes a fresh sampling decision.
            expect(coordinator.replayId, isNot('paused-reload'));
            expect(coordinator.recordingState, RecordingState.recording);
          },
        );
      }

      for (final enableIdleTimer in [true, false]) {
        test(
          'persists and clears background expiry with activity timer=$enableIdleTimer',
          () async {
            // GIVEN independently configured activity and background deadlines.
            final now = DateTime.utc(2026, 9, 28, 12);
            final writes = <(String, int, int, int?)>[];
            final coordinator = createCoordinator(
              idleTimeout: enableIdleTimer ? const Duration(minutes: 30) : null,
              maxSessionDuration: const Duration(hours: 24),
              backgroundBehavior: const ReplayBackgroundBehavior.pause(
                idleTimeout: Duration(minutes: 1),
              ),
              persistIdleExpiry: (id, idle, max, background) async {
                writes.add((id, idle, max, background));
              },
            );
            addTearDown(coordinator.dispose);

            await withClock(Clock.fixed(now), () async {
              coordinator.startRecording();
              await pumpEventQueue();
              expect(writes.last.$4, isNull);
              final activeIdle = writes.last.$2;
              final replayId = coordinator.replayId;

              // WHEN the page pauses.
              coordinator.onAppBackgrounded();
              await pumpEventQueue();

              // THEN background retention is persisted without replacing activity idle.
              expect(
                writes.last.$4,
                now.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
              );
              expect(writes.last.$2, activeIdle);

              // WHEN it returns before expiry without any new capture/interaction.
              coordinator.onAppForegrounded();
              await pumpEventQueue();

              // THEN only the background deadline is cleared, even with idle disabled.
              expect(coordinator.replayId, replayId);
              expect(writes.last.$4, isNull);
              expect(writes.last.$2, activeIdle);
            });
          },
        );
      }

      test(
        'resumed reload clears background expiry without resetting activity idle',
        () async {
          final now = DateTime.utc(2026, 9, 28, 12);
          final idleExpiry = now.add(const Duration(minutes: 2));
          final writes = <(String, int, int, int?)>[];
          final coordinator = createCoordinator(
            idleTimeout: const Duration(minutes: 30),
            maxSessionDuration: const Duration(hours: 24),
            persistIdleExpiry: (id, idle, max, background) async {
              writes.add((id, idle, max, background));
            },
          );
          addTearDown(coordinator.dispose);
          stageResume(
            Session(
              id: 'valid-reload',
              startTime: now,
              status: SessionStatus.active,
            ),
            idleExpiry: idleExpiry,
            backgroundExpiry: now.add(const Duration(seconds: 30)),
          );
          await withClock(Clock.fixed(now), () async {
            coordinator.onAppForegrounded();
            await pumpEventQueue();
          });
          expect(coordinator.replayId, 'valid-reload');
          expect(writes.last.$2, idleExpiry.millisecondsSinceEpoch);
          expect(writes.last.$4, isNull);
        },
      );

      test(
        'expired staged idle deadline is not resumed after settings',
        () async {
          final start = DateTime.utc(2026, 9, 28, 12);
          final coordinator = createCoordinator(
            autoRecordSessionsPercent: 100,
            idleTimeout: const Duration(minutes: 30),
            maxSessionDuration: const Duration(hours: 24),
          );
          addTearDown(coordinator.dispose);
          withClock(Clock.fixed(start), () {
            stageResume(
              Session(
                id: 'expired-staged',
                startTime: start,
                status: SessionStatus.active,
              ),
              idleExpiry: start.add(const Duration(seconds: 1)),
            );
          });
          await withClock(
            Clock.fixed(start.add(const Duration(seconds: 2))),
            () async {
              coordinator.onAppForegrounded();
              await pumpEventQueue();
              expect(coordinator.replayId, isNot('expired-staged'));
            },
          );
        },
      );

      test(
        'explicit stop after idle expiration prevents activity restart',
        () async {
          final coordinator = createCoordinator(autoRecordSessionsPercent: 100);
          addTearDown(coordinator.dispose);
          coordinator.startRecording();
          await pumpEventQueue();
          coordinator.handleIdleTimeout();
          coordinator.stopRecording();
          coordinator.onUserActivity();
          await pumpEventQueue();
          expect(coordinator.recordingState, RecordingState.notRecording);
        },
      );
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

          stageResume(session);

          expect(coordinator.recordingState, RecordingState.notRecording);
          expect(coordinator.replayId, isNull);

          coordinator.onAppForegrounded();
          await pumpEventQueue();

          expect(coordinator.recordingState, RecordingState.recording);
          expect(coordinator.replayId, 'pending-session');
        },
      );

      test('a manual start before settings arrive supersedes a staged '
          'session', () async {
        // GIVEN a staged session waiting on the first settings fetch
        final persisted = <(String, int, int)>[];
        settingsService = SettingsService(
          storageProvider: SettingsStorageProvider(
            token: 'test-token',
            logger: logger,
          ),
          token: 'test-token',
          logger: logger,
          httpClient: createFakeSettingsClient(isEnabled: true),
        );
        final coordinator = createCoordinator(
          autoRecordSessionsPercent: 100,
          maxSessionDuration: const Duration(hours: 24),
          persistIdleExpiry: (id, idle, max, background) async {
            persisted.add((id, idle, max));
          },
        );
        stageResume(
          Session(
            id: 'staged-session',
            startTime: DateTime.now().toUtc(),
            status: SessionStatus.active,
          ),
        );
        coordinator.onAppForegrounded();

        // WHEN the app starts recording before the settings verdict lands
        coordinator.startRecording(sessionsPercent: 100);
        final manualReplayId = coordinator.replayId;
        await pumpEventQueue();

        // THEN the verdict does not swap the staged session in, and the
        // staged session is expired so a reload cannot resume it either
        expect(manualReplayId, isNot('staged-session'));
        expect(coordinator.replayId, manualReplayId);
        expect(coordinator.recordingState, RecordingState.recording);
        expect(persisted.map((call) => call.$1), contains('staged-session'));
      });

      test('explicit stop cancels a staged session', () async {
        final session = Session(
          id: 'cancelled-session',
          startTime: DateTime.now().toUtc(),
          status: SessionStatus.active,
        );
        final coordinator = createCoordinator();
        stageResume(session);

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
      for (final input in [
        'wheel',
        'trackpad',
        'trackpad update',
        'keyboard',
        'key repeat',
      ]) {
        testWidgets('should leave idle timeout when receiving $input input', (
          tester,
        ) async {
          // Web replay sends super properties through the analytics plugin.
          const analyticsChannel = MethodChannel('mixpanel_flutter');
          final messenger = tester.binding.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(
            analyticsChannel,
            (_) async => null,
          );
          addTearDown(
            () => messenger.setMockMethodCallHandler(analyticsChannel, null),
          );
          // GIVEN a replay that timed out while its input detector stayed mounted.
          final coordinator = createCoordinator(autoRecordSessionsPercent: 100);
          final focusNode = FocusNode();
          var appKeyEvents = 0;
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: InteractionDetector(
                coordinator: coordinator,
                child: Focus(
                  focusNode: focusNode,
                  onKeyEvent: (_, _) {
                    appKeyEvents++;
                    return KeyEventResult.handled;
                  },
                  child: const ColoredBox(
                    color: Color(0xFFFFFFFF),
                    child: SizedBox.expand(),
                  ),
                ),
              ),
            ),
          );
          focusNode.requestFocus();
          coordinator.startRecording();
          await tester.pump();
          final originalReplayId = coordinator.replayId;
          expect(originalReplayId, isNotNull);
          if (input == 'key repeat') {
            await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
          }
          if (input == 'trackpad update') {
            await tester.sendEventToBinding(
              const PointerPanZoomStartEvent(position: Offset(100, 100)),
            );
          }
          coordinator.handleIdleTimeout();
          expect(coordinator.recordingState, RecordingState.notRecording);

          try {
            // WHEN activity arrives without a new pointer-down event.
            switch (input) {
              case 'wheel':
                await tester.sendEventToBinding(
                  const PointerScrollEvent(
                    position: Offset(100, 100),
                    scrollDelta: Offset(0, 50),
                  ),
                );
              case 'trackpad':
                await tester.sendEventToBinding(
                  const PointerPanZoomStartEvent(position: Offset(100, 100)),
                );
              case 'trackpad update':
                await tester.sendEventToBinding(
                  const PointerPanZoomUpdateEvent(
                    position: Offset(100, 100),
                    pan: Offset(0, 50),
                    panDelta: Offset(0, 50),
                  ),
                );
              case 'keyboard':
                await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
              case 'key repeat':
                await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
            }
            await tester.pump();

            // THEN a new replay starts, and app keyboard handling still runs.
            expect(coordinator.recordingState, RecordingState.recording);
            expect(coordinator.replayId, isNot(originalReplayId));
            if (input == 'keyboard' || input == 'key repeat') {
              expect(appKeyEvents, input == 'keyboard' ? 1 : 2);
              expect(focusNode.hasFocus, isTrue);

              // Key release alone must not restart a recording.
              coordinator.handleIdleTimeout();
              await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
              await tester.pump();
              expect(coordinator.recordingState, RecordingState.notRecording);

              // Removing the detector must remove its global keyboard observer.
              await tester.pumpWidget(const SizedBox());
              await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
              await tester.pump();
              expect(coordinator.recordingState, RecordingState.notRecording);
            }
          } finally {
            if (input.startsWith('trackpad')) {
              await tester.sendEventToBinding(
                const PointerPanZoomEndEvent(position: Offset(100, 100)),
              );
            }
            await tester.pumpWidget(const SizedBox());
            focusNode.dispose();
            await coordinator.dispose();
          }
        });
      }

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

      test('refreshes the idle window while recording', () {
        fakeAsync((async) {
          // GIVEN a recording session with a ten second idle window
          final coordinator = createCoordinator(
            autoRecordSessionsPercent: 100,
            idleTimeout: const Duration(seconds: 10),
            maxSessionDuration: const Duration(hours: 24),
          );
          coordinator.startRecording(sessionsPercent: 100);
          async.flushMicrotasks();
          expect(coordinator.recordingState, RecordingState.recording);
          final replayId = coordinator.replayId;

          // WHEN keyboard, wheel, or trackpad activity arrives at nine
          // seconds, with no successful capture to refresh the window
          async.elapse(const Duration(seconds: 9));
          coordinator.onUserActivity();

          // THEN the session outlives its original deadline
          async.elapse(const Duration(seconds: 5));
          expect(coordinator.recordingState, RecordingState.recording);
          expect(coordinator.replayId, replayId);

          // AND still idles out ten seconds after the last activity
          async.elapse(const Duration(seconds: 6));
          expect(coordinator.recordingState, RecordingState.notRecording);
        });
      });

      test('a screenshot capture does not extend the idle window', () {
        // Like mixpanel-js, only user input keeps a session alive. A screen
        // that repaints on its own (animation, live data) still idles out.
        fakeAsync((async) {
          final coordinator = createCoordinator(
            idleTimeout: const Duration(seconds: 10),
            maxSessionDuration: const Duration(hours: 24),
            capturer: _ImmediateCapturer(logger: logger),
          );
          coordinator.startRecording(sessionsPercent: 100);
          async.flushMicrotasks();
          expect(coordinator.recordingState, RecordingState.recording);

          // WHEN a frame is captured at nine seconds with no input
          async.elapse(const Duration(seconds: 9));
          coordinator.captureSnapshot(
            RenderRepaintBoundary(),
            boundaryElement: const SizedBox().createElement(),
          );
          async.flushMicrotasks();
          expect(eventQueue.eventCount, greaterThan(0), reason: 'captured');

          // THEN the session still idles out at ten seconds
          async.elapse(const Duration(seconds: 2));
          expect(coordinator.recordingState, RecordingState.notRecording);
        });
      });

      test('a drag keeps the idle window open', () {
        fakeAsync((async) {
          final coordinator = createCoordinator(
            idleTimeout: const Duration(seconds: 10),
            maxSessionDuration: const Duration(hours: 24),
          );
          coordinator.startRecording(sessionsPercent: 100);
          async.flushMicrotasks();

          async.elapse(const Duration(seconds: 9));
          coordinator.captureTouchMove([
            const TouchPosition(x: 1, y: 2, timeOffset: 0),
          ], clock.now());

          async.elapse(const Duration(seconds: 5));
          expect(coordinator.recordingState, RecordingState.recording);
        });
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
        final coordinator = createCoordinator(
          autoRecordSessionsPercent: 100,
          remoteSettingsMode: RemoteSettingsMode.fallback,
          idleTimeout: const Duration(minutes: 30),
          maxSessionDuration: const Duration(hours: 24),
          persistIdleExpiry: (_, idle, max, background) async {
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
            persistIdleExpiry: (_, idle, max, background) async {
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
        final coordinator = createCoordinator(
          autoRecordSessionsPercent: 100,
          idleTimeout: const Duration(minutes: 30),
          maxSessionDuration: const Duration(hours: 24),
          persistIdleExpiry: (_, idle, max, background) async {
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
            stageResume(stale);
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

        // WHEN
        final coordinator = createCoordinator(
          idleTimeout: const Duration(minutes: 30),
        );
        coordinator.startRecording(sessionsPercent: 100.0);
        await pumpEventQueue();

        // THEN
        expect(coordinator.recordingState, RecordingState.recording);
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
        final coordinator = createCoordinator(
          idleTimeout: const Duration(minutes: 30),
          maxSessionDuration: const Duration(hours: 24),
          persistIdleExpiry:
              (
                sessionId,
                idleExpiresMs,
                maxExpiresMs,
                backgroundExpiresMs,
              ) async {
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
      });
    });

    group('PR #283 review findings', () {
      test(
        'resuming a persisted session keeps its remaining idle window',
        () async {
          // GIVEN a persisted session whose 30 minute idle deadline is 2
          // minutes away
          final coordinator = createCoordinator(
            autoRecordSessionsPercent: 100,
            backgroundBehavior: const ReplayBackgroundBehavior.pause(
              idleTimeout: Duration(minutes: 30),
            ),
            idleTimeout: const Duration(minutes: 30),
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
            stageResume(session, idleExpiry: storedDeadline);
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
          final coordinator = createCoordinator(
            autoRecordSessionsPercent: 100,
            backgroundBehavior: const ReplayBackgroundBehavior.pause(
              idleTimeout: Duration(minutes: 30),
            ),
            idleTimeout: const Duration(minutes: 30),
          );
          final now = DateTime.utc(2026, 1, 1, 12);
          final session = Session(
            id: 'resumed-no-deadline',
            startTime: now,
            status: SessionStatus.active,
          );

          // WHEN it resumes and returns 5 minutes later
          await withClock(Clock.fixed(now), () async {
            stageResume(session);
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

      test('web keeps recording while hidden', () async {
        // GIVEN a web coordinator recording a session
        final coordinator = createCoordinator(
          autoRecordSessionsPercent: 100,
          backgroundBehavior: null,
        );
        coordinator.startRecording(sessionsPercent: 100);
        await pumpEventQueue();
        final replayId = coordinator.replayId;
        expect(replayId, isNotNull);

        // WHEN the tab is hidden
        coordinator.onAppBackgrounded();
        await pumpEventQueue();

        // THEN the replay continues, as in mixpanel-js; only its idle and
        // maximum deadlines can end it
        expect(coordinator.recordingState, RecordingState.recording);
        expect(coordinator.replayId, replayId);
        expect(coordinator.isAppInForeground, isFalse);
      });

      test('web keeps the same session after the tab is shown again', () async {
        // GIVEN a web coordinator recording a session
        final coordinator = createCoordinator(
          autoRecordSessionsPercent: 100,
          backgroundBehavior: null,
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
            backgroundBehavior: null,
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

      test('should store the deadlines when the page is hidden right after '
          'activity', () async {
        // GIVEN a recording web session that just stored its deadlines
        final writes = <String>[];
        final coordinator = createCoordinator(
          autoRecordSessionsPercent: 100,
          backgroundBehavior: null,
          idleTimeout: const Duration(minutes: 30),
          maxSessionDuration: const Duration(hours: 24),
          persistIdleExpiry: (id, idle, max, background) async {
            writes.add(id);
          },
        );
        coordinator.startRecording(sessionsPercent: 100);
        await pumpEventQueue();
        coordinator.captureInteraction(0, Offset.zero, DateTime.now());
        final before = writes.length;

        // WHEN the page is hidden inside the activity-write debounce
        coordinator.onAppBackgrounded();
        await pumpEventQueue();

        // THEN the latest deadlines are written at once, since a hidden page
        // may be frozen or discarded before the next write
        expect(writes.length, before + 1);
      });

      test('web keeps \$mp_replay_id registered while hidden', () async {
        // GIVEN a recording web session, with sender traffic captured
        final calls = recordSenderCalls();
        final coordinator = createCoordinator(
          autoRecordSessionsPercent: 100,
          backgroundBehavior: null,
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

        // THEN events tracked while hidden still carry the replay ID, as in
        // mixpanel-js, whose replay continues across tab switches
        expect(calls, isNot(contains('unregisterSuperProperty')));
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
            backgroundBehavior: null,
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
          backgroundBehavior: null,
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
          final coordinator = createCoordinator(
            autoRecordSessionsPercent: 100,
            backgroundBehavior: null,
            idleTimeout: const Duration(minutes: 30),
          );
          final hiddenAt = DateTime.utc(2026, 1, 1, 12);
          String? replayId;
          await withClock(Clock.fixed(hiddenAt), () async {
            coordinator.startRecording(sessionsPercent: 100);
            await pumpEventQueue();
            replayId = coordinator.replayId;
            coordinator.onAppBackgrounded();
            await pumpEventQueue();
            // Hidden, and the replay keeps recording, as in mixpanel-js.
            expect(coordinator.recordingState, RecordingState.recording);
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
          final coordinator = createCoordinator(
            autoRecordSessionsPercent: 100,
            backgroundBehavior: null,
            idleTimeout: const Duration(minutes: 30),
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
          backgroundBehavior: null,
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

    group('resume before metadata exists', () {
      test('the first deadline write lands once metadata exists', () async {
        // GIVEN a session whose metadata write is still pending when the page
        // is hidden and shown again
        final gated = _GatedMetadataQueue();
        await gated.initialize();
        addTearDown(gated.dispose);
        final recorder = EventRecorder(
          eventQueue: gated,
          sessionManager: sessionManager,
          getDistinctId: () => 'user-1',
          logger: logger,
        );
        final writesWithMetadata = <String>[];
        final coordinator = createCoordinator(
          autoRecordSessionsPercent: 100,
          recorder: recorder,
          idleTimeout: const Duration(minutes: 30),
          maxSessionDuration: const Duration(hours: 24),
          backgroundBehavior: null,
          persistIdleExpiry: (sessionId, idle, max, background) async {
            // Mirrors IndexedDB, where a deadline write for a session with no
            // metadata record is a silent no-op.
            if (await gated.getSessionMetadata(sessionId) != null) {
              writesWithMetadata.add(sessionId);
            }
          },
        );
        coordinator.startRecording(sessionsPercent: 100);
        final sessionId = sessionManager.getCurrentSession().id;
        coordinator.onAppBackgrounded();
        coordinator.onAppForegrounded();
        await pumpEventQueue();
        expect(coordinator.recordingState, RecordingState.initializing);
        expect(writesWithMetadata, isEmpty, reason: 'no record to update yet');

        // WHEN the metadata write finally completes
        gated.releaseMetadata();
        await pumpEventQueue();

        // THEN a deadline is persisted immediately instead of waiting for the
        // next debounced activity write
        expect(writesWithMetadata, [sessionId]);
      });
    });

    group('stopRecording persisted expiry', () {
      test('stop expires the recorded session in storage', () async {
        // GIVEN an active web recording
        final persisted = <(String, int, int)>[];
        final coordinator = createCoordinator(
          idleTimeout: const Duration(minutes: 30),
          maxSessionDuration: const Duration(hours: 24),
          persistIdleExpiry: (id, idle, max, background) async {
            persisted.add((id, idle, max));
          },
        );
        final now = DateTime.utc(2026, 1, 1);
        await withClock(Clock.fixed(now), () async {
          coordinator.startRecording(sessionsPercent: 100);
          await pumpEventQueue();
        });
        final sessionId = coordinator.replayId!;

        // WHEN the app stops recording
        withClock(Clock.fixed(now), coordinator.stopRecording);

        // THEN both persisted deadlines are already in the past, so a reload
        // cannot resume the stopped session
        final expiredMs = now.millisecondsSinceEpoch - 1;
        expect(persisted.last, (sessionId, expiredMs, expiredMs));
      });

      test('stop expires a staged resumable session', () async {
        // GIVEN a persisted session waiting for remote settings
        final persisted = <(String, int, int)>[];
        final coordinator = createCoordinator(
          maxSessionDuration: const Duration(hours: 24),
          persistIdleExpiry: (id, idle, max, background) async {
            persisted.add((id, idle, max));
          },
        );
        stageResume(
          Session(
            id: 'staged-session',
            startTime: DateTime.now().toUtc(),
            status: SessionStatus.active,
          ),
        );
        final now = DateTime.utc(2026, 1, 1);

        // WHEN the app stops recording before the session resumes
        withClock(Clock.fixed(now), coordinator.stopRecording);

        // THEN the staged session is expired in storage
        final expiredMs = now.millisecondsSinceEpoch - 1;
        expect(persisted, [('staged-session', expiredMs, expiredMs)]);
      });

      test('stop during initialization expires the session once its '
          'metadata exists', () async {
        // GIVEN a recording whose metadata has not been persisted yet
        final persisted = <(String, int, int)>[];
        final coordinator = createCoordinator(
          maxSessionDuration: const Duration(hours: 24),
          persistIdleExpiry: (id, idle, max, background) async {
            persisted.add((id, idle, max));
          },
        );
        final now = DateTime.utc(2026, 1, 1);

        // WHEN it is stopped before the metadata write completes
        late final String sessionId;
        await withClock(Clock.fixed(now), () async {
          coordinator.startRecording(sessionsPercent: 100);
          sessionId = coordinator.replayId!;
          coordinator.stopRecording();
          await pumpEventQueue();
        });

        // THEN the last write for that session expires it
        final expiredMs = now.millisecondsSinceEpoch - 1;
        expect(persisted.last, (sessionId, expiredMs, expiredMs));
        expect(coordinator.recordingState, RecordingState.notRecording);
      });

      test('background stop behavior expires the session', () async {
        // GIVEN an active recording configured to stop in the background
        final persisted = <(String, int, int)>[];
        final coordinator = createCoordinator(
          idleTimeout: const Duration(minutes: 30),
          maxSessionDuration: const Duration(hours: 24),
          persistIdleExpiry: (id, idle, max, background) async {
            persisted.add((id, idle, max));
          },
        );
        final now = DateTime.utc(2026, 1, 1);
        await withClock(Clock.fixed(now), () async {
          coordinator.startRecording(sessionsPercent: 100);
          await pumpEventQueue();
        });
        final sessionId = coordinator.replayId!;

        // WHEN the page is hidden
        withClock(Clock.fixed(now), coordinator.onAppBackgrounded);

        // THEN the session cannot be resumed by a later page load
        final expiredMs = now.millisecondsSinceEpoch - 1;
        expect(persisted.last, (sessionId, expiredMs, expiredMs));
      });
    });

    group('recording duration limits', () {
      test('remote durations above 24 hours are capped', () async {
        // GIVEN remote limits beyond mixpanel-js's 24-hour maximum
        const twoDaysMs = 2 * 24 * 60 * 60 * 1000;
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
              'record_max_ms': twoDaysMs,
              'record_idle_timeout_ms': twoDaysMs,
            },
          ),
        );
        final deadlines = <(int, int)>[];
        final coordinator = createCoordinator(
          autoRecordSessionsPercent: 100,
          remoteSettingsMode: RemoteSettingsMode.fallback,
          maxSessionDuration: const Duration(hours: 24),
          persistIdleExpiry: (_, idle, max, background) async {
            deadlines.add((idle, max));
          },
        );
        final now = DateTime.utc(2026, 1, 1);

        // WHEN remote settings arrive and recording starts
        await withClock(Clock.fixed(now), () async {
          coordinator.onAppForegrounded();
          await pumpEventQueue();
        });

        // THEN both deadlines are 24 hours out
        const dayMs = 24 * 60 * 60 * 1000;
        expect(deadlines.single, (
          now.millisecondsSinceEpoch + dayMs,
          now.millisecondsSinceEpoch + dayMs,
        ));
      });

      for (final (name, record)
          in <(String, void Function(SessionReplayCoordinator))>[
            (
              'tap',
              (coordinator) =>
                  coordinator.captureInteraction(0, Offset.zero, clock.now()),
            ),
            (
              'drag',
              (coordinator) => coordinator.captureTouchMove([
                const TouchPosition(x: 1, y: 2, timeOffset: 0),
              ], clock.now()),
            ),
          ]) {
        test('a $name past the maximum ends the replay even before the '
            'timer fires', () async {
          // GIVEN a recording whose maximum passes while its timer is held
          // back, as browser suspension can do
          final start = DateTime.utc(2026, 1, 1);
          final coordinator = createCoordinator(
            maxSessionDuration: const Duration(minutes: 1),
          );
          addTearDown(coordinator.dispose);
          await withClock(Clock.fixed(start), () async {
            coordinator.startRecording(sessionsPercent: 100);
            await pumpEventQueue();
          });
          final expiredReplayId = coordinator.replayId;
          expect(coordinator.recordingState, RecordingState.recording);

          // WHEN input arrives after the maximum by wall clock
          withClock(
            Clock.fixed(start.add(const Duration(minutes: 2))),
            () => record(coordinator),
          );

          // THEN the replay ends and the next activity starts a new one
          expect(coordinator.recordingState, RecordingState.notRecording);
          coordinator.onUserActivity();
          expect(coordinator.replayId, isNot(expiredReplayId));
        });
      }
    });
  });
}

class _DelayedMetadataQueue extends InMemoryEventQueue {
  final ready = Completer<void>();

  @override
  Future<void> createSessionMetadata(Session session) async {
    await ready.future;
    await super.createSessionMetadata(session);
  }
}

/// Queue that holds session metadata creation until [releaseMetadata], so a
/// test can drive lifecycle transitions while the record does not exist yet.
class _GatedMetadataQueue extends InMemoryEventQueue {
  final Completer<void> _gate = Completer<void>();

  @override
  Future<void> createSessionMetadata(Session session) async {
    await _gate.future;
    await super.createSessionMetadata(session);
  }

  void releaseMetadata() {
    if (!_gate.isCompleted) _gate.complete();
  }
}

/// Capturer that returns a small successful frame without touching the
/// render tree, for tests about what a capture does and does not trigger.
class _ImmediateCapturer extends ScreenshotCapturer {
  _ImmediateCapturer({required super.logger})
    : super(
        directive: MaskingDirective(autoMaskTypes: {}),
        debugOverlayEnabled: false,
        frameAcquirer: ToImageFrameAcquirer(
          DartPngCompressor(),
          logger: MixpanelLogger(LogLevel.none),
        ),
      );

  @override
  Future<CaptureResult> capture(
    RenderRepaintBoundary boundary, {
    required Session Function() getCurrentSession,
    required String Function() getDistinctId,
    required Element boundaryElement,
    Set<AutoMaskedView>? maskTypes,
    bool Function()? isCancelled,
    void Function()? onRenderTreeRead,
  }) async => CaptureSuccess(
    data: Uint8List.fromList([1, 2, 3]),
    width: 10,
    height: 10,
    maskCount: 0,
    timestamp: clock.now(),
    sessionId: getCurrentSession().id,
    distinctId: getDistinctId(),
    maskRegions: const [],
  );
}

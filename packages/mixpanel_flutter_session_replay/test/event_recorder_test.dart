import 'dart:typed_data';
import 'dart:ui';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/event_recorder.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session/session_manager.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session_event.dart';
import 'package:mixpanel_flutter_session_replay/src/models/wireframe.dart';
import 'package:mixpanel_flutter_session_replay/src/models/wireframes_options.dart'
    show MaskDecision;

import 'helpers/in_memory_event_queue.dart';

void main() {
  group('EventRecorder', () {
    late InMemoryEventQueue eventQueue;
    late SessionManager sessionManager;
    late EventRecorder recorder;
    late Session session;

    final defaultDistinctId = 'user-123';

    setUp(() async {
      eventQueue = InMemoryEventQueue();
      await eventQueue.initialize();
      sessionManager = SessionManager();
      session = sessionManager.startNewSession();
      await eventQueue.createSessionMetadata(session);

      recorder = EventRecorder(
        eventQueue: eventQueue,
        sessionManager: sessionManager,
        getDistinctId: () => defaultDistinctId,
        logger: MixpanelLogger(LogLevel.none),
      );
    });

    tearDown(() async {
      try {
        await eventQueue.dispose();
      } catch (_) {
        // Already disposed by test
      }
    });

    group('recordSession', () {
      test('creates session metadata in queue', () async {
        // GIVEN
        final newSession = Session(
          id: 'new-session-id',
          startTime: DateTime.fromMillisecondsSinceEpoch(5000, isUtc: true),
          status: SessionStatus.active,
        );

        // WHEN
        await recorder.recordSession(newSession);

        // THEN
        final metadata = await eventQueue.getSessionMetadata('new-session-id');
        expect(metadata, isNotNull);
        expect(metadata!.id, newSession.id);
      });

      test('does not throw on storage error', () async {
        // GIVEN
        await eventQueue.dispose(); // Force errors

        final newSession = Session(
          id: 'session-error',
          startTime: clock.now(),
          status: SessionStatus.active,
        );

        // WHEN / THEN - should not throw
        await recorder.recordSession(newSession);
      });

      test('resets metadata dimensions so new session emits metadata', () async {
        // GIVEN - first session has a screenshot (sets _lastMetadataDimensions)
        await recorder.recordSnapshot(
          imageData: Uint8List(0),
          width: 375,
          height: 812,
          timestamp: clock.now(),
        );

        // Drain old session events from queue
        final oldEvents = await eventQueue.fetchBatch(
          sessionId: session.id,
          distinctId: defaultDistinctId,
          maxBytes: 100000,
          maxCount: 10,
        );
        await eventQueue.remove(oldEvents);

        // Start a new session (simulates background→foreground cycle)
        final newSession = sessionManager.startNewSession();
        await recorder.recordSession(newSession);

        // WHEN - first screenshot of the new session with same dimensions
        await recorder.recordSnapshot(
          imageData: Uint8List(0),
          width: 375,
          height: 812,
          timestamp: clock.now(),
        );

        // THEN - new session should have its own metadata event
        final events = await eventQueue.fetchBatch(
          sessionId: newSession.id,
          distinctId: defaultDistinctId,
          maxBytes: 100000,
          maxCount: 10,
        );

        expect(events.length, 2); // metadata + screenshot
        expect(events[0].type, EventType.metadata);
        expect(events[1].type, EventType.screenshot);

        final metadata = events[0].payload as MetadataPayload;
        expect(metadata.width, 375);
        expect(metadata.height, 812);
      });
    });

    group('recordSnapshot', () {
      test('saves screenshot event to queue', () async {
        // GIVEN
        final expectedImageData = Uint8List.fromList([1, 2, 3, 4, 5]);
        final expectedTimestamp = DateTime.fromMillisecondsSinceEpoch(
          1000,
          isUtc: true,
        );

        // WHEN
        await recorder.recordSnapshot(
          imageData: expectedImageData,
          width: 100,
          height: 200,
          timestamp: expectedTimestamp,
        );

        // THEN
        final oldest = await eventQueue.fetchOldest();
        final events = await eventQueue.fetchBatch(
          sessionId: oldest!.sessionId,
          distinctId: oldest.distinctId,
          maxBytes: 100000,
          maxCount: 10,
        );

        // metadata + screenshot
        expect(events.length, 2);

        final screenshotEvent = events[1];
        expect(screenshotEvent.type, EventType.screenshot);
        expect(screenshotEvent.sessionId, session.id);
        expect(screenshotEvent.distinctId, defaultDistinctId);
        expect(screenshotEvent.timestamp, expectedTimestamp);

        final payload = screenshotEvent.payload as ScreenshotPayload;
        expect(payload.imageData, expectedImageData);
      });

      test('records metadata event on first screenshot', () async {
        // GIVEN
        final expectedWidth = 375;
        final expectedHeight = 812;

        // WHEN
        await recorder.recordSnapshot(
          imageData: Uint8List(0),
          width: expectedWidth,
          height: expectedHeight,
          timestamp: clock.now(),
        );

        // THEN
        final oldest = await eventQueue.fetchOldest();
        final events = await eventQueue.fetchBatch(
          sessionId: oldest!.sessionId,
          distinctId: oldest.distinctId,
          maxBytes: 100000,
          maxCount: 10,
        );

        final metadataEvent = events[0];
        expect(metadataEvent.type, EventType.metadata);

        final payload = metadataEvent.payload as MetadataPayload;
        expect(payload.width, expectedWidth);
        expect(payload.height, expectedHeight);
      });

      test('records metadata event when dimensions change', () async {
        // GIVEN - first screenshot establishes initial dimensions
        await recorder.recordSnapshot(
          imageData: Uint8List(0),
          width: 375,
          height: 812,
          timestamp: clock.now(),
        );

        final expectedNewWidth = 812;
        final expectedNewHeight = 375;

        // WHEN - second screenshot with different dimensions
        await recorder.recordSnapshot(
          imageData: Uint8List(0),
          width: expectedNewWidth,
          height: expectedNewHeight,
          timestamp: clock.now(),
        );

        // THEN - should have 2 metadata events + 2 screenshots = 4 events
        final oldest = await eventQueue.fetchOldest();
        final events = await eventQueue.fetchBatch(
          sessionId: oldest!.sessionId,
          distinctId: oldest.distinctId,
          maxBytes: 100000,
          maxCount: 10,
        );

        expect(events.length, 4);
        expect(events[0].type, EventType.metadata); // first dimensions
        expect(events[1].type, EventType.screenshot);
        expect(events[2].type, EventType.metadata); // changed dimensions
        expect(events[3].type, EventType.screenshot);

        final secondMetadata = events[2].payload as MetadataPayload;
        expect(secondMetadata.width, expectedNewWidth);
        expect(secondMetadata.height, expectedNewHeight);
      });

      test(
        'does not record duplicate metadata when dimensions unchanged',
        () async {
          // GIVEN
          final width = 375;
          final height = 812;
          final expectedEventCount = 3; // 1 metadata + 2 screenshots

          // WHEN
          await recorder.recordSnapshot(
            imageData: Uint8List(0),
            width: width,
            height: height,
            timestamp: clock.now(),
          );
          await recorder.recordSnapshot(
            imageData: Uint8List(0),
            width: width,
            height: height,
            timestamp: clock.now(),
          );

          // THEN
          final oldest = await eventQueue.fetchOldest();
          final events = await eventQueue.fetchBatch(
            sessionId: oldest!.sessionId,
            distinctId: oldest.distinctId,
            maxBytes: 100000,
            maxCount: 10,
          );

          expect(events.length, expectedEventCount);
          expect(events[0].type, EventType.metadata);
          expect(events[1].type, EventType.screenshot);
          expect(events[2].type, EventType.screenshot);
        },
      );
    });

    group('recordInteraction', () {
      test('saves interaction event with correct coordinates', () async {
        // GIVEN
        final expectedInteractionType = 1;
        final expectedX = 150.5;
        final expectedY = 300.75;
        final expectedTimestamp = DateTime.fromMillisecondsSinceEpoch(
          4200,
          isUtc: true,
        );

        // WHEN
        await recorder.recordInteraction(
          expectedInteractionType,
          Offset(expectedX, expectedY),
          expectedTimestamp,
        );

        // THEN
        final oldest = await eventQueue.fetchOldest();
        final events = await eventQueue.fetchBatch(
          sessionId: oldest!.sessionId,
          distinctId: oldest.distinctId,
          maxBytes: 100000,
          maxCount: 10,
        );

        expect(events.length, 1);

        final event = events[0];
        expect(event.type, EventType.interaction);
        expect(event.sessionId, session.id);
        expect(event.distinctId, defaultDistinctId);
        expect(event.timestamp, expectedTimestamp);

        final payload = event.payload as InteractionPayload;
        expect(payload.interactionType, expectedInteractionType);
        expect(payload.x, expectedX);
        expect(payload.y, expectedY);
      });

      test('does not throw on storage error', () async {
        // GIVEN
        await eventQueue.dispose();

        // WHEN / THEN - should not throw
        await recorder.recordInteraction(1, Offset(10, 20), DateTime.now());
      });
    });

    group('recordTouchMove', () {
      test(
        'saves touch move event with supplied positions and timestamp',
        () async {
          // GIVEN
          final expectedPositions = const [
            TouchPosition(x: 10.0, y: 20.0, timeOffset: -100),
            TouchPosition(x: 30.0, y: 40.0, timeOffset: 0),
          ];
          final expectedTimestamp = DateTime.fromMillisecondsSinceEpoch(
            7100,
            isUtc: true,
          );

          // WHEN
          await recorder.recordTouchMove(
            positions: expectedPositions,
            timestamp: expectedTimestamp,
          );

          // THEN
          final oldest = await eventQueue.fetchOldest();
          final events = await eventQueue.fetchBatch(
            sessionId: oldest!.sessionId,
            distinctId: oldest.distinctId,
            maxBytes: 100000,
            maxCount: 10,
          );

          expect(events.length, 1);
          expect(events[0].type, EventType.touchMove);
          expect(events[0].timestamp, expectedTimestamp);

          final payload = events[0].payload as TouchMovePayload;
          expect(payload.positions, expectedPositions);
        },
      );

      test('skips empty position batches', () async {
        // WHEN
        await recorder.recordTouchMove(
          positions: const [],
          timestamp: DateTime.now(),
        );

        // THEN - nothing queued
        expect(await eventQueue.fetchOldest(), isNull);
      });

      test('does not throw on storage error', () async {
        // GIVEN
        await eventQueue.dispose();

        // WHEN / THEN - should not throw
        await recorder.recordTouchMove(
          positions: const [TouchPosition(x: 1, y: 2, timeOffset: 0)],
          timestamp: DateTime.now(),
        );
      });
    });

    group('recordWireframe', () {
      test('saves wireframe event to queue with supplied timestamp', () async {
        // GIVEN
        final expectedTimestamp = DateTime.fromMillisecondsSinceEpoch(
          9000,
          isUtc: true,
        );
        final payload = WireframePayload(
          viewportWidth: 400,
          viewportHeight: 800,
          elements: [
            WireframeElement(
              role: WireframeRole.text,
              text: 'Hello',
              bounds: const Rect.fromLTWH(0, 0, 40, 20),
              maskDecision: MaskDecision.none,
            ),
          ],
        );

        // WHEN
        await recorder.recordWireframe(
          payload: payload,
          timestamp: expectedTimestamp,
        );

        // THEN
        final oldest = await eventQueue.fetchOldest();
        final events = await eventQueue.fetchBatch(
          sessionId: oldest!.sessionId,
          distinctId: oldest.distinctId,
          maxBytes: 100000,
          maxCount: 10,
        );

        expect(events, hasLength(1));
        final saved = events.single;
        expect(saved.type, EventType.wireframe);
        expect(saved.timestamp, expectedTimestamp);
        expect(saved.sessionId, session.id);
        expect(saved.distinctId, defaultDistinctId);

        final wireframe = saved.payload as WireframePayload;
        expect(wireframe.viewportWidth, 400);
        expect(wireframe.viewportHeight, 800);
        expect(wireframe.elements.single.text, 'Hello');
      });

      test('does not throw on storage error', () async {
        // GIVEN
        await eventQueue.dispose();
        final payload = WireframePayload(
          viewportWidth: 100,
          viewportHeight: 100,
          elements: const [],
        );

        // WHEN / THEN — should not throw
        await recorder.recordWireframe(
          payload: payload,
          timestamp: clock.now(),
        );
      });
    });

    group('recordMetadata', () {
      test('saves metadata event with correct dimensions', () async {
        // GIVEN
        final expectedWidth = 1080;
        final expectedHeight = 1920;

        // WHEN
        await recorder.recordMetadata(
          expectedWidth,
          expectedHeight,
          clock.now(),
        );

        // THEN
        final oldest = await eventQueue.fetchOldest();
        final events = await eventQueue.fetchBatch(
          sessionId: oldest!.sessionId,
          distinctId: oldest.distinctId,
          maxBytes: 100000,
          maxCount: 10,
        );

        expect(events.length, 1);

        final event = events[0];
        expect(event.type, EventType.metadata);

        final payload = event.payload as MetadataPayload;
        expect(payload.width, expectedWidth);
        expect(payload.height, expectedHeight);
      });
    });

    group('distinctId tracking', () {
      test('uses current distinctId for events', () async {
        // GIVEN
        var currentDistinctId = 'user-A';
        final dynamicRecorder = EventRecorder(
          eventQueue: eventQueue,
          sessionManager: sessionManager,
          getDistinctId: () => currentDistinctId,
          logger: MixpanelLogger(LogLevel.none),
        );

        // WHEN - record with first distinctId
        await dynamicRecorder.recordInteraction(
          1,
          Offset(10, 20),
          DateTime.now(),
        );

        // Change distinctId
        currentDistinctId = 'user-B';

        // Record with second distinctId
        await dynamicRecorder.recordInteraction(
          2,
          Offset(30, 40),
          DateTime.now(),
        );

        // THEN - first event uses original distinctId
        final oldest = await eventQueue.fetchOldest();
        final firstBatch = await eventQueue.fetchBatch(
          sessionId: oldest!.sessionId,
          distinctId: 'user-A',
          maxBytes: 100000,
          maxCount: 10,
        );
        expect(firstBatch.length, 1);
        expect(firstBatch[0].distinctId, 'user-A');

        // Remove first batch to get to second
        await eventQueue.remove(firstBatch);

        final nextOldest = await eventQueue.fetchOldest();
        expect(nextOldest!.distinctId, 'user-B');
      });
    });

    group('dispose', () {
      test('disposes event queue', () async {
        // GIVEN - recorder is active

        // WHEN
        await recorder.dispose();

        // THEN - queue operations should fail after dispose
        expect(() => eventQueue.fetchOldest(), throwsA(anything));
      });
    });
  });
}

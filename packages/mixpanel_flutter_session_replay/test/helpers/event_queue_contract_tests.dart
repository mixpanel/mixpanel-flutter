import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/storage/event_queue_interface.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session_event.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session.dart';

/// Asserts that all [EventQueue] methods throw [StateError] before
/// initialization.
///
/// Call inside a `test()` body. The caller handles setup/cleanup of the
/// uninitialized [storage] instance.
void assertUninitializedState(EventQueue storage) {
  final event = SessionReplayEvent(
    sessionId: 'session1',
    distinctId: 'user1',
    timestamp: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
    type: EventType.interaction,
    payload: InteractionPayload(interactionType: 1, x: 0, y: 0),
  );

  expect(() => storage.add(event), throwsStateError);
  expect(() => storage.fetchOldest(), throwsStateError);
  expect(() => storage.fetchNewest(), throwsStateError);
  expect(() => storage.fetchOldestHeader(), throwsStateError);
  expect(() => storage.fetchNewestHeader(), throwsStateError);
  expect(
    () => storage.fetchBatch(
      sessionId: 'session1',
      distinctId: 'user1',
      maxBytes: 5000000,
      maxCount: 100,
    ),
    throwsStateError,
  );
  expect(() => storage.remove([]), throwsStateError);
  expect(() => storage.removeAll(), throwsStateError);
  expect(() => storage.getLastSequenceNumber('session1'), throwsStateError);
  expect(() => storage.updateSequenceNumber('session1', 1), throwsStateError);
  expect(
    () => storage.createSessionMetadata(
      Session(
        id: 'session1',
        startTime: DateTime.now(),
        status: SessionStatus.active,
      ),
    ),
    throwsStateError,
  );
  expect(() => storage.getSessionMetadata('session1'), throwsStateError);
}

/// Runs the full [EventQueue] contract test suite against an
/// already-initialized queue.
///
/// Call inside a `group()` whose `setUp` creates and initializes the storage
/// and whose `tearDown` disposes and cleans it up. [getStorage] returns the
/// current instance (e.g. `() => storage`).
void runEventQueueContractTests(EventQueue Function() getStorage) {
  group('Basic Operations', () {
    test('stores and retrieves events', () async {
      final storage = getStorage();
      final sessionId = 'session1';
      final event = SessionReplayEvent(
        sessionId: sessionId,
        distinctId: 'user1',
        timestamp: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
        type: EventType.interaction,
        payload: InteractionPayload(interactionType: 1, x: 10, y: 20),
      );

      await storage.add(event);

      final oldest = await storage.fetchOldest();
      expect(oldest, isNotNull);
      expect(oldest!.sessionId, sessionId);
      expect(oldest.distinctId, 'user1');
      expect(oldest.timestamp.millisecondsSinceEpoch, 100);
      expect(oldest.type, EventType.interaction);
      expect(oldest.id, isPositive);
      expect(oldest.dataSize, isPositive);
      final payload = oldest.payload as InteractionPayload;
      expect(payload.interactionType, 1);
      expect(payload.x, 10);
      expect(payload.y, 20);
    });

    test('round-trips screenshot binary data', () async {
      final storage = getStorage();
      final bytes = Uint8List.fromList(<int>[0, 1, 2, 127, 128, 254, 255]);
      await storage.add(
        SessionReplayEvent(
          sessionId: 'binary-session',
          distinctId: 'user1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
          type: EventType.screenshot,
          payload: ScreenshotPayload(imageData: bytes),
        ),
      );

      final stored = await storage.fetchOldest();
      expect(stored, isNotNull);
      expect(stored!.payload, isA<ScreenshotPayload>());
      expect((stored.payload as ScreenshotPayload).imageData, bytes);
    });

    test('returns null when no events exist', () async {
      final storage = getStorage();
      final oldest = await storage.fetchOldest();
      expect(oldest, isNull);

      final newest = await storage.fetchNewest();
      expect(newest, isNull);

      expect(await storage.fetchOldestHeader(), isNull);
      expect(await storage.fetchNewestHeader(), isNull);
    });

    test('returns payload-free oldest and newest headers', () async {
      final storage = getStorage();
      await storage.add(
        SessionReplayEvent(
          sessionId: 'first-session',
          distinctId: 'first-user',
          timestamp: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
          type: EventType.screenshot,
          payload: ScreenshotPayload(imageData: Uint8List(1024)),
        ),
      );
      await storage.add(
        SessionReplayEvent(
          sessionId: 'last-session',
          distinctId: 'last-user',
          timestamp: DateTime.fromMillisecondsSinceEpoch(200, isUtc: true),
          type: EventType.interaction,
          payload: InteractionPayload(interactionType: 1, x: 1, y: 2),
        ),
      );

      final oldest = await storage.fetchOldestHeader();
      final newest = await storage.fetchNewestHeader();

      expect(oldest, isNotNull);
      expect(oldest!.id, isPositive);
      expect(oldest.sessionId, 'first-session');
      expect(oldest.distinctId, 'first-user');
      expect(oldest.timestamp.millisecondsSinceEpoch, 100);
      expect(newest, isNotNull);
      expect(newest!.id, greaterThan(oldest.id));
      expect(newest.sessionId, 'last-session');
      expect(newest.distinctId, 'last-user');
      expect(newest.timestamp.millisecondsSinceEpoch, 200);
    });

    test('fetchNewest returns most recently added event', () async {
      final storage = getStorage();
      final event1 = SessionReplayEvent(
        sessionId: 'session1',
        distinctId: 'user1',
        timestamp: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
        type: EventType.interaction,
        payload: InteractionPayload(interactionType: 1, x: 0, y: 0),
      );
      final event2 = SessionReplayEvent(
        sessionId: 'session1',
        distinctId: 'user1',
        timestamp: DateTime.fromMillisecondsSinceEpoch(200, isUtc: true),
        type: EventType.interaction,
        payload: InteractionPayload(interactionType: 2, x: 10, y: 20),
      );

      await storage.add(event1);
      await storage.add(event2);

      final newest = await storage.fetchNewest();
      expect(newest, isNotNull);
      expect(newest!.timestamp.millisecondsSinceEpoch, 200);

      final oldest = await storage.fetchOldest();
      expect(oldest, isNotNull);
      expect(oldest!.timestamp.millisecondsSinceEpoch, 100);
    });

    test('deletes events by ID', () async {
      final storage = getStorage();
      final sessionId = 'session1';

      // Store 3 events
      for (int i = 0; i < 3; i++) {
        final event = SessionReplayEvent(
          sessionId: sessionId,
          distinctId: 'user1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            100 + (i * 100),
            isUtc: true,
          ),
          type: EventType.interaction,
          payload: InteractionPayload(interactionType: 1, x: 0, y: 0),
        );
        await storage.add(event);
      }

      // Get first 2 events
      var oldest = await storage.fetchOldest();
      final batch = await storage.fetchBatch(
        sessionId: oldest!.sessionId,
        distinctId: oldest.distinctId,
        maxBytes: 5000000,
        maxCount: 2,
      );
      expect(batch.length, 2);

      // Delete them
      await storage.remove(batch);

      // Should only have 1 event left
      oldest = await storage.fetchOldest();
      final remaining = await storage.fetchBatch(
        sessionId: oldest!.sessionId,
        distinctId: oldest.distinctId,
        maxBytes: 5000000,
        maxCount: 100,
      );
      expect(remaining.length, 1);
      expect(remaining[0].timestamp.millisecondsSinceEpoch, 300);
    });

    test('handles empty delete list', () async {
      final storage = getStorage();
      // Should not throw
      await storage.remove([]);
    });
  });

  group('Cross-Session FIFO Processing', () {
    test('returns oldest session events first across all sessions', () async {
      final storage = getStorage();
      // Store events in different sessions
      final event1 = SessionReplayEvent(
        sessionId: 'session1',
        distinctId: 'user1',
        timestamp: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
        type: EventType.interaction,
        payload: InteractionPayload(interactionType: 1, x: 0, y: 0),
      );

      final event2 = SessionReplayEvent(
        sessionId: 'session2',
        distinctId: 'user1',
        timestamp: DateTime.fromMillisecondsSinceEpoch(200, isUtc: true),
        type: EventType.interaction,
        payload: InteractionPayload(interactionType: 1, x: 0, y: 0),
      );

      await storage.add(event1);
      await storage.add(event2);

      // Query for oldest - should return session1 (oldest session)
      final oldest = await storage.fetchOldest();
      final batch = await storage.fetchBatch(
        sessionId: oldest!.sessionId,
        distinctId: oldest.distinctId,
        maxBytes: 5000000,
        maxCount: 100,
      );

      expect(batch.length, 1);
      expect(batch[0].sessionId, 'session1');
      expect(batch[0].timestamp.millisecondsSinceEpoch, 100);
    });

    test('fetches a requested session when another session is older', () async {
      final storage = getStorage();
      await storage.add(
        SessionReplayEvent(
          sessionId: 'older-session',
          distinctId: 'user1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
          type: EventType.interaction,
          payload: InteractionPayload(interactionType: 1, x: 0, y: 0),
        ),
      );
      await storage.add(
        SessionReplayEvent(
          sessionId: 'requested-session',
          distinctId: 'user2',
          timestamp: DateTime.fromMillisecondsSinceEpoch(200, isUtc: true),
          type: EventType.interaction,
          payload: InteractionPayload(interactionType: 1, x: 0, y: 0),
        ),
      );

      final batch = await storage.fetchBatch(
        sessionId: 'requested-session',
        distinctId: 'user2',
        maxBytes: 5000000,
        maxCount: 100,
      );

      expect(batch, hasLength(1));
      expect(batch.single.sessionId, 'requested-session');
    });
  });

  group('Sequence Number Persistence', () {
    test('stores and retrieves sequence number', () async {
      final storage = getStorage();
      final sessionId = 'session1';
      final startTime = DateTime.now();
      final session = Session(
        id: sessionId,
        startTime: startTime,
        status: SessionStatus.active,
      );

      // Create session metadata first
      await storage.createSessionMetadata(session);

      await storage.updateSequenceNumber(sessionId, 5);
      final retrieved = await storage.getLastSequenceNumber(sessionId);

      expect(retrieved, 5);
    });

    test('returns -1 for non-existent session', () async {
      final storage = getStorage();
      final seqNum = await storage.getLastSequenceNumber('non-existent');
      expect(seqNum, -1);
    });

    test('updates existing sequence number', () async {
      final storage = getStorage();
      final sessionId = 'session1';
      final startTime = DateTime.now();
      final session = Session(
        id: sessionId,
        startTime: startTime,
        status: SessionStatus.active,
      );

      // Create session metadata first
      await storage.createSessionMetadata(session);

      await storage.updateSequenceNumber(sessionId, 5);
      await storage.updateSequenceNumber(sessionId, 10);

      final retrieved = await storage.getLastSequenceNumber(sessionId);
      expect(retrieved, 10);
    });

    test(
      'throws error when updating sequence for non-existent session',
      () async {
        final storage = getStorage();
        final sessionId = 'session1';

        // Try to update sequence without creating metadata first
        expect(
          () => storage.updateSequenceNumber(sessionId, 5),
          throwsStateError,
        );
      },
    );

    test('does not overwrite session metadata on duplicate create', () async {
      final storage = getStorage();
      final sessionId = 'session1';
      final originalSession = Session(
        id: sessionId,
        startTime: DateTime.fromMillisecondsSinceEpoch(1000000, isUtc: true),
        status: SessionStatus.active,
      );
      await storage.createSessionMetadata(originalSession);

      // Create metadata again with different start time
      final duplicateSession = Session(
        id: sessionId,
        startTime: DateTime.fromMillisecondsSinceEpoch(9999999, isUtc: true),
        status: SessionStatus.active,
      );
      await storage.createSessionMetadata(duplicateSession);

      // Should retain the original start time
      final session = await storage.getSessionMetadata(sessionId);
      expect(session, isNotNull);
      expect(session!.startTime.millisecondsSinceEpoch, 1000000);
    });
  });

  group('Clear Event Cache', () {
    test('clears all events and metadata', () async {
      final storage = getStorage();
      final sessionId = 'session1';
      final session = Session(
        id: sessionId,
        startTime: DateTime.now(),
        status: SessionStatus.active,
      );

      // Create session metadata
      await storage.createSessionMetadata(session);

      // Store some events
      final event = SessionReplayEvent(
        sessionId: sessionId,
        distinctId: 'user1',
        timestamp: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
        type: EventType.interaction,
        payload: InteractionPayload(interactionType: 1, x: 0, y: 0),
      );
      await storage.add(event);

      // Store sequence number
      await storage.updateSequenceNumber(sessionId, 5);

      // Clear cache
      await storage.removeAll();

      // Verify everything is cleared
      final oldest = await storage.fetchOldest();
      expect(oldest, isNull);

      final seqNum = await storage.getLastSequenceNumber(sessionId);
      expect(seqNum, -1);
    });
  });

  group('Upload Batching - DistinctId Boundary Tests', () {
    test('stops at distinctId boundary when switching users', () async {
      final storage = getStorage();
      // Setup: anonymous -> user@example.com -> anonymous (again)
      final sessionId = 'session1';

      final event1 = SessionReplayEvent(
        sessionId: sessionId,
        distinctId: 'anonymous123',
        timestamp: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
        type: EventType.interaction,
        payload: InteractionPayload(interactionType: 1, x: 0, y: 0),
      );

      final event2 = SessionReplayEvent(
        sessionId: sessionId,
        distinctId: 'anonymous123',
        timestamp: DateTime.fromMillisecondsSinceEpoch(200, isUtc: true),
        type: EventType.interaction,
        payload: InteractionPayload(interactionType: 1, x: 0, y: 0),
      );

      final event3 = SessionReplayEvent(
        sessionId: sessionId,
        distinctId: 'user@example.com',
        timestamp: DateTime.fromMillisecondsSinceEpoch(300, isUtc: true),
        type: EventType.interaction,
        payload: InteractionPayload(interactionType: 1, x: 0, y: 0),
      );

      final event4 = SessionReplayEvent(
        sessionId: sessionId,
        distinctId: 'anonymous123',
        timestamp: DateTime.fromMillisecondsSinceEpoch(400, isUtc: true),
        type: EventType.interaction,
        payload: InteractionPayload(interactionType: 1, x: 0, y: 0),
      );

      // Store all events
      await storage.add(event1);
      await storage.add(event2);
      await storage.add(event3);
      await storage.add(event4);

      // Batch 1: Query for oldest (should be anonymous123)
      var oldest = await storage.fetchOldest();
      final batch1 = await storage.fetchBatch(
        sessionId: oldest!.sessionId,
        distinctId: oldest.distinctId,
        maxBytes: 5000000,
        maxCount: 100,
      );

      // Should get events 1 and 2 (stop at boundary before event 3)
      expect(batch1.length, 2);
      expect(batch1[0].timestamp.millisecondsSinceEpoch, 100);
      expect(batch1[0].distinctId, 'anonymous123');
      expect(batch1[1].timestamp.millisecondsSinceEpoch, 200);
      expect(batch1[1].distinctId, 'anonymous123');

      // Delete batch 1
      await storage.remove(batch1);

      // Batch 2: Query for oldest (should now be user@example.com)
      oldest = await storage.fetchOldest();
      final batch2 = await storage.fetchBatch(
        sessionId: oldest!.sessionId,
        distinctId: oldest.distinctId,
        maxBytes: 5000000,
        maxCount: 100,
      );

      // Should get only event 3 (stop at boundary before event 4)
      expect(batch2.length, 1);
      expect(batch2[0].timestamp.millisecondsSinceEpoch, 300);
      expect(batch2[0].distinctId, 'user@example.com');

      // Delete batch 2
      await storage.remove(batch2);

      // Batch 3: Query for oldest (should now be anonymous123 again, event 4)
      oldest = await storage.fetchOldest();
      final batch3 = await storage.fetchBatch(
        sessionId: oldest!.sessionId,
        distinctId: oldest.distinctId,
        maxBytes: 5000000,
        maxCount: 100,
      );

      // Should get event 4
      expect(batch3.length, 1);
      expect(batch3[0].timestamp.millisecondsSinceEpoch, 400);
      expect(batch3[0].distinctId, 'anonymous123');
    });

    test(
      'respects size limit while staying within distinctId boundary',
      () async {
        final storage = getStorage();
        final sessionId = 'session1';

        // Create events with known sizes
        final event1 = SessionReplayEvent(
          sessionId: sessionId,
          distinctId: 'user1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
          type: EventType.screenshot,
          payload: ScreenshotPayload(
            imageData: Uint8List(500),
          ), // ~513 bytes total
        );

        final event2 = SessionReplayEvent(
          sessionId: sessionId,
          distinctId: 'user1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(200, isUtc: true),
          type: EventType.screenshot,
          payload: ScreenshotPayload(
            imageData: Uint8List(800),
          ), // ~813 bytes total
        );

        final event3 = SessionReplayEvent(
          sessionId: sessionId,
          distinctId: 'user1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(300, isUtc: true),
          type: EventType.screenshot,
          payload: ScreenshotPayload(
            imageData: Uint8List(1000),
          ), // ~1013 bytes total
        );

        await storage.add(event1);
        await storage.add(event2);
        await storage.add(event3);

        // Query with 1500 byte limit
        // Event1 (513 bytes) + Event2 (813 bytes) = 1326 bytes total
        // Event1 + Event2 + Event3 would be 2339 bytes
        final oldest = await storage.fetchOldest();
        final batch = await storage.fetchBatch(
          sessionId: oldest!.sessionId,
          distinctId: oldest.distinctId,
          maxBytes: 1500,
          maxCount: 100,
        );

        // Should get events 1 and 2, but not 3
        expect(batch.length, 2);
        expect(batch[0].timestamp.millisecondsSinceEpoch, 100);
        expect(batch[1].timestamp.millisecondsSinceEpoch, 200);
      },
    );

    test(
      'respects count limit while staying within distinctId boundary',
      () async {
        final storage = getStorage();
        final sessionId = 'session1';

        // Create 5 events for same user
        for (int i = 0; i < 5; i++) {
          final event = SessionReplayEvent(
            sessionId: sessionId,
            distinctId: 'user1',
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              100 + (i * 100),
              isUtc: true,
            ),
            type: EventType.interaction,
            payload: InteractionPayload(interactionType: 1, x: 0, y: 0),
          );
          await storage.add(event);
        }

        // Query with count limit of 3
        final oldest = await storage.fetchOldest();
        final batch = await storage.fetchBatch(
          sessionId: oldest!.sessionId,
          distinctId: oldest.distinctId,
          maxBytes: 5000000,
          maxCount: 3,
        );

        // Should get only 3 events
        expect(batch.length, 3);
        expect(batch[0].timestamp.millisecondsSinceEpoch, 100);
        expect(batch[1].timestamp.millisecondsSinceEpoch, 200);
        expect(batch[2].timestamp.millisecondsSinceEpoch, 300);
      },
    );

    test(
      'returns one oversized event so the queue can make progress',
      () async {
        final storage = getStorage();
        await storage.add(
          SessionReplayEvent(
            sessionId: 'session1',
            distinctId: 'user1',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
            type: EventType.screenshot,
            payload: ScreenshotPayload(imageData: Uint8List(2000)),
          ),
        );

        final batch = await storage.fetchBatch(
          sessionId: 'session1',
          distinctId: 'user1',
          maxBytes: 100,
          maxCount: 100,
        );

        expect(batch, hasLength(1));
      },
    );
  });
}

/// Runs quota enforcement tests using a factory that creates and initializes
/// a 1MB-quota [EventQueue] instance.
///
/// The factory must return a fresh, initialized queue with `quotaMB: 1`.
/// The queue is disposed automatically via [addTearDown].
void runQuotaEnforcementTests(
  Future<EventQueue> Function() createQuotaLimitedStorage,
) {
  group('Quota Enforcement', () {
    test('drops new events when quota is exceeded', () async {
      final storage = await createQuotaLimitedStorage();
      addTearDown(() => storage.dispose());

      final sessionId = 'session1';

      // Add a 900KB screenshot to fill most of the 1MB quota
      final largeEvent = SessionReplayEvent(
        sessionId: sessionId,
        distinctId: 'user1',
        timestamp: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
        type: EventType.screenshot,
        payload: ScreenshotPayload(imageData: Uint8List(900000)),
      );
      await storage.add(largeEvent);

      // Verify large event was stored
      var oldest = await storage.fetchOldest();
      var batch = await storage.fetchBatch(
        sessionId: oldest!.sessionId,
        distinctId: oldest.distinctId,
        maxBytes: 5000000,
        maxCount: 100,
      );
      expect(batch.length, 1);

      // Try to store another large event (should be dropped - would exceed 1MB)
      final anotherLargeEvent = SessionReplayEvent(
        sessionId: sessionId,
        distinctId: 'user1',
        timestamp: DateTime.fromMillisecondsSinceEpoch(200, isUtc: true),
        type: EventType.screenshot,
        payload: ScreenshotPayload(imageData: Uint8List(200000)),
      );
      await storage.add(anotherLargeEvent);

      // Should still only have 1 event (second event was dropped)
      oldest = await storage.fetchOldest();
      batch = await storage.fetchBatch(
        sessionId: oldest!.sessionId,
        distinctId: oldest.distinctId,
        maxBytes: 5000000,
        maxCount: 100,
      );
      expect(batch.length, 1);
      expect(batch[0].timestamp.millisecondsSinceEpoch, 100);
    });

    test('repeated deletion does not create phantom quota capacity', () async {
      final storage = await createQuotaLimitedStorage();
      addTearDown(() => storage.dispose());

      SessionReplayEvent screenshot(int timestamp, int byteCount) =>
          SessionReplayEvent(
            sessionId: 'session1',
            distinctId: 'user1',
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              timestamp,
              isUtc: true,
            ),
            type: EventType.screenshot,
            payload: ScreenshotPayload(imageData: Uint8List(byteCount)),
          );

      await storage.add(screenshot(100, 900000));
      final original = await storage.fetchBatch(
        sessionId: 'session1',
        distinctId: 'user1',
        maxBytes: 5000000,
        maxCount: 100,
      );
      await storage.remove(original);
      await storage.remove(original);

      await storage.add(screenshot(200, 900000));
      await storage.add(screenshot(300, 200000));

      final remaining = await storage.fetchBatch(
        sessionId: 'session1',
        distinctId: 'user1',
        maxBytes: 5000000,
        maxCount: 100,
      );
      expect(remaining, hasLength(1));
      expect(remaining.single.timestamp.millisecondsSinceEpoch, 200);
    });
  });
}

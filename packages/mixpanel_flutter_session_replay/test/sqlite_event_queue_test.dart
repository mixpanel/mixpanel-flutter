import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/storage/sqlite_event_queue.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session_event.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'dart:typed_data';

void main() {
  // Initialize sqflite for testing
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Database File Naming', () {
    test('creates database file with sanitized token name', () async {
      final tempDir = await Directory.systemTemp.createTemp('mixpanel_test_');
      final storage = SqliteEventQueue(
        token: 'my-project-token',
        storageDir: tempDir,
        logger: MixpanelLogger(LogLevel.none),
      );
      await storage.initialize();

      final dbFile = File(
        '${tempDir.path}/mixpanel_replay_my-project-token.db',
      );
      expect(dbFile.existsSync(), true);

      await storage.dispose();
      await tempDir.delete(recursive: true);
    });

    test('sanitizes special characters in token for filename', () async {
      final tempDir = await Directory.systemTemp.createTemp('mixpanel_test_');
      final storage = SqliteEventQueue(
        token: 'token/with@special!chars',
        storageDir: tempDir,
        logger: MixpanelLogger(LogLevel.none),
      );
      await storage.initialize();

      final dbFile = File(
        '${tempDir.path}/mixpanel_replay_token_with_special_chars.db',
      );
      expect(dbFile.existsSync(), true);

      await storage.dispose();
      await tempDir.delete(recursive: true);
    });
  });

  group('Uninitialized State', () {
    test('throws StateError when calling methods before initialize', () async {
      final tempDir = await Directory.systemTemp.createTemp('mixpanel_test_');
      final storage = SqliteEventQueue(
        token: 'test-token',
        storageDir: tempDir,
        logger: MixpanelLogger(LogLevel.none),
      );

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
      expect(
        () => storage.updateSequenceNumber('session1', 1),
        throwsStateError,
      );
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

      await tempDir.delete(recursive: true);
    });
  });

  group('SqliteEventQueue', () {
    late SqliteEventQueue storage;
    late Directory tempDir;

    setUp(() async {
      // Create temp directory for test database
      tempDir = await Directory.systemTemp.createTemp('mixpanel_test_');
      storage = SqliteEventQueue(
        token: 'test-token',
        storageDir: tempDir,
        logger: MixpanelLogger(LogLevel.none),
      );
      await storage.initialize();
    });

    tearDown(() async {
      await storage.dispose();
      await tempDir.delete(recursive: true);
    });

    group('Basic Operations', () {
      test('stores and retrieves events', () async {
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

      test('returns null when no events exist', () async {
        final oldest = await storage.fetchOldest();
        expect(oldest, isNull);

        final newest = await storage.fetchNewest();
        expect(newest, isNull);
      });

      test('fetchNewest returns most recently added event', () async {
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
        // Should not throw
        await storage.remove([]);
      });
    });

    group('Cross-Session FIFO Processing', () {
      test('returns oldest session events first across all sessions', () async {
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
    });

    group('Sequence Number Persistence', () {
      test('stores and retrieves sequence number', () async {
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
        final seqNum = await storage.getLastSequenceNumber('non-existent');
        expect(seqNum, -1);
      });

      test('updates existing sequence number', () async {
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
          final sessionId = 'session1';

          // Try to update sequence without creating metadata first
          expect(
            () => storage.updateSequenceNumber(sessionId, 5),
            throwsStateError,
          );
        },
      );

      test('does not overwrite session metadata on duplicate create', () async {
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

    group('Quota Enforcement', () {
      test('drops new events when quota is exceeded', () async {
        // Create storage with 1MB quota (smallest unit since quotaMB is int)
        await storage.dispose();
        await tempDir.delete(recursive: true);
        tempDir = await Directory.systemTemp.createTemp('mixpanel_test_');

        storage = SqliteEventQueue(
          token: 'test-token',
          storageDir: tempDir,
          quotaMB: 1, // 1MB quota
          logger: MixpanelLogger(LogLevel.none),
        );
        await storage.initialize();

        final sessionId = 'session1';

        // Add a 900KB screenshot to fill most of the 1MB quota
        final largeEvent = SessionReplayEvent(
          sessionId: sessionId,
          distinctId: 'user1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
          type: EventType.screenshot,
          payload: ScreenshotPayload(imageData: Uint8List(900000)), // 900KB
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
          payload: ScreenshotPayload(imageData: Uint8List(200000)), // 200KB
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
    });

    group('Clear Event Cache', () {
      test('clears all events and metadata', () async {
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
  });

  group('Upload Batching - DistinctId Boundary Tests', () {
    late SqliteEventQueue storage;
    late Directory tempDir;

    setUp(() async {
      // Create temp directory for test database
      tempDir = await Directory.systemTemp.createTemp('mixpanel_test_');
      storage = SqliteEventQueue(
        token: 'test-token',
        storageDir: tempDir,
        logger: MixpanelLogger(LogLevel.none),
      );
      await storage.initialize();
    });

    tearDown(() async {
      await storage.dispose();
      await tempDir.delete(recursive: true);
    });

    test('stops at distinctId boundary when switching users', () async {
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
        // Event1 (513 bytes) + Event2 (813 bytes) = 1326 bytes total ✓
        // Event1 + Event2 + Event3 would be 2339 bytes ✗
        final oldest = await storage.fetchOldest();
        final batch = await storage.fetchBatch(
          sessionId: oldest!.sessionId,
          distinctId: oldest.distinctId,
          maxBytes: 1500,
          maxCount: 100,
        );

        // Should get events 1 and 2, but not 3 (running total stops at 1326 < 1500)
        expect(batch.length, 2);
        expect(batch[0].timestamp.millisecondsSinceEpoch, 100);
        expect(batch[1].timestamp.millisecondsSinceEpoch, 200);
      },
    );

    test(
      'respects count limit while staying within distinctId boundary',
      () async {
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
  });
}

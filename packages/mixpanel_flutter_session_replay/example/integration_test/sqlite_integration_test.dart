import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/storage/sqlite_event_queue.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session_event.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final logger = MixpanelLogger(LogLevel.none);

  /// Creates a unique temp subdirectory for each test to avoid interference.
  Future<Directory> createTestDir(String testName) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final sanitized = testName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final dir = Directory(
      '${tempDir.path}/mixpanel_integration_test_${sanitized}_$timestamp',
    );
    await dir.create(recursive: true);
    return dir;
  }

  testWidgets('initializes database without errors', (tester) async {
    await tester.runAsync(() async {
      final dir = await createTestDir('init');
      try {
        final queue = SqliteEventQueue(
          token: 'test-token',
          storageDir: dir,
          logger: logger,
        );

        await queue.initialize();
        await queue.dispose();
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  testWidgets('stores and retrieves interaction event', (tester) async {
    await tester.runAsync(() async {
      final dir = await createTestDir('interaction');
      final queue = SqliteEventQueue(
        token: 'test-token',
        storageDir: dir,
        logger: logger,
      );
      try {
        await queue.initialize();

        final event = SessionReplayEvent(
          sessionId: 'session1',
          distinctId: 'user1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
          type: EventType.interaction,
          payload: InteractionPayload(interactionType: 1, x: 10.5, y: 20.3),
        );

        await queue.add(event);

        final oldest = await queue.fetchOldest();
        expect(oldest, isNotNull);
        expect(oldest!.sessionId, 'session1');
        expect(oldest.distinctId, 'user1');
        expect(oldest.timestamp.millisecondsSinceEpoch, 100);
        expect(oldest.type, EventType.interaction);
        expect(oldest.id, isPositive);
        expect(oldest.dataSize, isPositive);

        final payload = oldest.payload as InteractionPayload;
        expect(payload.interactionType, 1);
        expect(payload.x, 10.5);
        expect(payload.y, 20.3);
      } finally {
        await queue.dispose();
        await dir.delete(recursive: true);
      }
    });
  });

  testWidgets('stores and retrieves screenshot event', (tester) async {
    await tester.runAsync(() async {
      final dir = await createTestDir('screenshot');
      final queue = SqliteEventQueue(
        token: 'test-token',
        storageDir: dir,
        logger: logger,
      );
      try {
        await queue.initialize();

        final imageData = Uint8List.fromList(
          List.generate(256, (i) => i % 256),
        );
        final event = SessionReplayEvent(
          sessionId: 'session1',
          distinctId: 'user1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(200, isUtc: true),
          type: EventType.screenshot,
          payload: ScreenshotPayload(imageData: imageData),
        );

        await queue.add(event);

        final oldest = await queue.fetchOldest();
        expect(oldest, isNotNull);
        expect(oldest!.type, EventType.screenshot);

        final payload = oldest.payload as ScreenshotPayload;
        expect(payload.imageData.length, imageData.length);
        expect(payload.imageData, imageData);
      } finally {
        await queue.dispose();
        await dir.delete(recursive: true);
      }
    });
  });

  testWidgets('fetchOldest and fetchNewest return correct ordering', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final dir = await createTestDir('ordering');
      final queue = SqliteEventQueue(
        token: 'test-token',
        storageDir: dir,
        logger: logger,
      );
      try {
        await queue.initialize();

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

        await queue.add(event1);
        await queue.add(event2);

        final oldest = await queue.fetchOldest();
        expect(oldest, isNotNull);
        expect(oldest!.timestamp.millisecondsSinceEpoch, 100);

        final newest = await queue.fetchNewest();
        expect(newest, isNotNull);
        expect(newest!.timestamp.millisecondsSinceEpoch, 200);
      } finally {
        await queue.dispose();
        await dir.delete(recursive: true);
      }
    });
  });

  testWidgets('deletes events by ID', (tester) async {
    await tester.runAsync(() async {
      final dir = await createTestDir('delete');
      final queue = SqliteEventQueue(
        token: 'test-token',
        storageDir: dir,
        logger: logger,
      );
      try {
        await queue.initialize();

        for (int i = 0; i < 3; i++) {
          await queue.add(
            SessionReplayEvent(
              sessionId: 'session1',
              distinctId: 'user1',
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                100 + (i * 100),
                isUtc: true,
              ),
              type: EventType.interaction,
              payload: InteractionPayload(interactionType: 1, x: 0, y: 0),
            ),
          );
        }

        // Fetch first 2 events
        final oldest = await queue.fetchOldest();
        final batch = await queue.fetchBatch(
          sessionId: oldest!.sessionId,
          distinctId: oldest.distinctId,
          maxBytes: 5000000,
          maxCount: 2,
        );
        expect(batch.length, 2);

        // Delete them
        await queue.remove(batch);

        // Should only have 1 event left
        final remaining = await queue.fetchOldest();
        expect(remaining, isNotNull);
        expect(remaining!.timestamp.millisecondsSinceEpoch, 300);

        final allRemaining = await queue.fetchBatch(
          sessionId: remaining.sessionId,
          distinctId: remaining.distinctId,
          maxBytes: 5000000,
          maxCount: 100,
        );
        expect(allRemaining.length, 1);
      } finally {
        await queue.dispose();
        await dir.delete(recursive: true);
      }
    });
  });

  testWidgets('batch respects size limit', (tester) async {
    await tester.runAsync(() async {
      final dir = await createTestDir('size_limit');
      final queue = SqliteEventQueue(
        token: 'test-token',
        storageDir: dir,
        logger: logger,
      );
      try {
        await queue.initialize();

        // Create events with known image sizes
        final event1 = SessionReplayEvent(
          sessionId: 'session1',
          distinctId: 'user1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
          type: EventType.screenshot,
          payload: ScreenshotPayload(imageData: Uint8List(500)),
        );
        final event2 = SessionReplayEvent(
          sessionId: 'session1',
          distinctId: 'user1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(200, isUtc: true),
          type: EventType.screenshot,
          payload: ScreenshotPayload(imageData: Uint8List(800)),
        );
        final event3 = SessionReplayEvent(
          sessionId: 'session1',
          distinctId: 'user1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(300, isUtc: true),
          type: EventType.screenshot,
          payload: ScreenshotPayload(imageData: Uint8List(1000)),
        );

        await queue.add(event1);
        await queue.add(event2);
        await queue.add(event3);

        // Query with 1500 byte limit - should get events 1 and 2 but not 3
        final oldest = await queue.fetchOldest();
        final batch = await queue.fetchBatch(
          sessionId: oldest!.sessionId,
          distinctId: oldest.distinctId,
          maxBytes: 1500,
          maxCount: 100,
        );

        expect(batch.length, 2);
        expect(batch[0].timestamp.millisecondsSinceEpoch, 100);
        expect(batch[1].timestamp.millisecondsSinceEpoch, 200);
      } finally {
        await queue.dispose();
        await dir.delete(recursive: true);
      }
    });
  });

  testWidgets('batch respects count limit', (tester) async {
    await tester.runAsync(() async {
      final dir = await createTestDir('count_limit');
      final queue = SqliteEventQueue(
        token: 'test-token',
        storageDir: dir,
        logger: logger,
      );
      try {
        await queue.initialize();

        for (int i = 0; i < 5; i++) {
          await queue.add(
            SessionReplayEvent(
              sessionId: 'session1',
              distinctId: 'user1',
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                100 + (i * 100),
                isUtc: true,
              ),
              type: EventType.interaction,
              payload: InteractionPayload(interactionType: 1, x: 0, y: 0),
            ),
          );
        }

        final oldest = await queue.fetchOldest();
        final batch = await queue.fetchBatch(
          sessionId: oldest!.sessionId,
          distinctId: oldest.distinctId,
          maxBytes: 5000000,
          maxCount: 3,
        );

        expect(batch.length, 3);
        expect(batch[0].timestamp.millisecondsSinceEpoch, 100);
        expect(batch[1].timestamp.millisecondsSinceEpoch, 200);
        expect(batch[2].timestamp.millisecondsSinceEpoch, 300);
      } finally {
        await queue.dispose();
        await dir.delete(recursive: true);
      }
    });
  });

  testWidgets('batch stops at distinctId boundary', (tester) async {
    await tester.runAsync(() async {
      final dir = await createTestDir('distinct_boundary');
      final queue = SqliteEventQueue(
        token: 'test-token',
        storageDir: dir,
        logger: logger,
      );
      try {
        await queue.initialize();

        // anonymous -> user@example.com -> anonymous
        await queue.add(
          SessionReplayEvent(
            sessionId: 'session1',
            distinctId: 'anonymous123',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
            type: EventType.interaction,
            payload: InteractionPayload(interactionType: 1, x: 0, y: 0),
          ),
        );
        await queue.add(
          SessionReplayEvent(
            sessionId: 'session1',
            distinctId: 'anonymous123',
            timestamp: DateTime.fromMillisecondsSinceEpoch(200, isUtc: true),
            type: EventType.interaction,
            payload: InteractionPayload(interactionType: 1, x: 0, y: 0),
          ),
        );
        await queue.add(
          SessionReplayEvent(
            sessionId: 'session1',
            distinctId: 'user@example.com',
            timestamp: DateTime.fromMillisecondsSinceEpoch(300, isUtc: true),
            type: EventType.interaction,
            payload: InteractionPayload(interactionType: 1, x: 0, y: 0),
          ),
        );
        await queue.add(
          SessionReplayEvent(
            sessionId: 'session1',
            distinctId: 'anonymous123',
            timestamp: DateTime.fromMillisecondsSinceEpoch(400, isUtc: true),
            type: EventType.interaction,
            payload: InteractionPayload(interactionType: 1, x: 0, y: 0),
          ),
        );

        // Batch 1: should get the 2 anonymous123 events, stopping before user@example.com
        var oldest = await queue.fetchOldest();
        final batch1 = await queue.fetchBatch(
          sessionId: oldest!.sessionId,
          distinctId: oldest.distinctId,
          maxBytes: 5000000,
          maxCount: 100,
        );

        expect(batch1.length, 2);
        expect(batch1[0].distinctId, 'anonymous123');
        expect(batch1[0].timestamp.millisecondsSinceEpoch, 100);
        expect(batch1[1].distinctId, 'anonymous123');
        expect(batch1[1].timestamp.millisecondsSinceEpoch, 200);

        // Delete batch 1, fetch batch 2
        await queue.remove(batch1);

        oldest = await queue.fetchOldest();
        final batch2 = await queue.fetchBatch(
          sessionId: oldest!.sessionId,
          distinctId: oldest.distinctId,
          maxBytes: 5000000,
          maxCount: 100,
        );

        expect(batch2.length, 1);
        expect(batch2[0].distinctId, 'user@example.com');
        expect(batch2[0].timestamp.millisecondsSinceEpoch, 300);

        // Delete batch 2, fetch batch 3
        await queue.remove(batch2);

        oldest = await queue.fetchOldest();
        final batch3 = await queue.fetchBatch(
          sessionId: oldest!.sessionId,
          distinctId: oldest.distinctId,
          maxBytes: 5000000,
          maxCount: 100,
        );

        expect(batch3.length, 1);
        expect(batch3[0].distinctId, 'anonymous123');
        expect(batch3[0].timestamp.millisecondsSinceEpoch, 400);
      } finally {
        await queue.dispose();
        await dir.delete(recursive: true);
      }
    });
  });

  testWidgets('quota enforcement drops events over limit', (tester) async {
    await tester.runAsync(() async {
      final dir = await createTestDir('quota');
      final queue = SqliteEventQueue(
        token: 'test-token',
        storageDir: dir,
        quotaMB: 1, // 1MB quota
        logger: logger,
      );
      try {
        await queue.initialize();

        // Add a 900KB screenshot to fill most of the 1MB quota
        await queue.add(
          SessionReplayEvent(
            sessionId: 'session1',
            distinctId: 'user1',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
            type: EventType.screenshot,
            payload: ScreenshotPayload(imageData: Uint8List(900000)),
          ),
        );

        // Verify first event was stored
        final oldest = await queue.fetchOldest();
        expect(oldest, isNotNull);

        // Try to add another event that would exceed quota
        await queue.add(
          SessionReplayEvent(
            sessionId: 'session1',
            distinctId: 'user1',
            timestamp: DateTime.fromMillisecondsSinceEpoch(200, isUtc: true),
            type: EventType.screenshot,
            payload: ScreenshotPayload(imageData: Uint8List(200000)),
          ),
        );

        // Should still only have the first event
        final batch = await queue.fetchBatch(
          sessionId: oldest!.sessionId,
          distinctId: oldest.distinctId,
          maxBytes: 5000000,
          maxCount: 100,
        );
        expect(batch.length, 1);
        expect(batch[0].timestamp.millisecondsSinceEpoch, 100);
      } finally {
        await queue.dispose();
        await dir.delete(recursive: true);
      }
    });
  });

  testWidgets('sequence number persistence', (tester) async {
    await tester.runAsync(() async {
      final dir = await createTestDir('sequence');
      final queue = SqliteEventQueue(
        token: 'test-token',
        storageDir: dir,
        logger: logger,
      );
      try {
        await queue.initialize();

        final session = Session(
          id: 'session1',
          startTime: DateTime.fromMillisecondsSinceEpoch(1000000, isUtc: true),
          status: SessionStatus.active,
        );

        // Create session metadata
        await queue.createSessionMetadata(session);

        // Verify initial sequence is -1
        var seqNum = await queue.getLastSequenceNumber('session1');
        expect(seqNum, -1);

        // Update and verify
        await queue.updateSequenceNumber('session1', 5);
        seqNum = await queue.getLastSequenceNumber('session1');
        expect(seqNum, 5);

        // Update again and verify latest value
        await queue.updateSequenceNumber('session1', 10);
        seqNum = await queue.getLastSequenceNumber('session1');
        expect(seqNum, 10);

        // Non-existent session returns -1
        seqNum = await queue.getLastSequenceNumber('non-existent');
        expect(seqNum, -1);
      } finally {
        await queue.dispose();
        await dir.delete(recursive: true);
      }
    });
  });

  testWidgets('database persists across dispose and reinitialize', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final dir = await createTestDir('persistence');
      try {
        // Create first queue instance, add data
        final queue1 = SqliteEventQueue(
          token: 'test-token',
          storageDir: dir,
          logger: logger,
        );
        await queue1.initialize();

        await queue1.add(
          SessionReplayEvent(
            sessionId: 'session1',
            distinctId: 'user1',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
            type: EventType.interaction,
            payload: InteractionPayload(interactionType: 1, x: 5, y: 10),
          ),
        );

        final session = Session(
          id: 'session1',
          startTime: DateTime.fromMillisecondsSinceEpoch(1000000, isUtc: true),
          status: SessionStatus.active,
        );
        await queue1.createSessionMetadata(session);
        await queue1.updateSequenceNumber('session1', 7);

        // Dispose the first queue
        await queue1.dispose();

        // Create a new queue instance with the same directory and token
        final queue2 = SqliteEventQueue(
          token: 'test-token',
          storageDir: dir,
          logger: logger,
        );
        await queue2.initialize();

        // Verify event persisted
        final oldest = await queue2.fetchOldest();
        expect(oldest, isNotNull);
        expect(oldest!.sessionId, 'session1');
        expect(oldest.timestamp.millisecondsSinceEpoch, 100);

        final payload = oldest.payload as InteractionPayload;
        expect(payload.x, 5);
        expect(payload.y, 10);

        // Verify sequence number persisted
        final seqNum = await queue2.getLastSequenceNumber('session1');
        expect(seqNum, 7);

        // Verify session metadata persisted
        final sessionMeta = await queue2.getSessionMetadata('session1');
        expect(sessionMeta, isNotNull);
        expect(sessionMeta!.startTime.millisecondsSinceEpoch, 1000000);

        await queue2.dispose();
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  testWidgets('removeAll clears events and metadata', (tester) async {
    await tester.runAsync(() async {
      final dir = await createTestDir('removeAll');
      final queue = SqliteEventQueue(
        token: 'test-token',
        storageDir: dir,
        logger: logger,
      );
      try {
        await queue.initialize();

        // Add events and metadata
        await queue.add(
          SessionReplayEvent(
            sessionId: 'session1',
            distinctId: 'user1',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
            type: EventType.interaction,
            payload: InteractionPayload(interactionType: 1, x: 0, y: 0),
          ),
        );

        final session = Session(
          id: 'session1',
          startTime: DateTime.now(),
          status: SessionStatus.active,
        );
        await queue.createSessionMetadata(session);
        await queue.updateSequenceNumber('session1', 5);

        // Clear everything
        await queue.removeAll();

        // Verify events are cleared
        final oldest = await queue.fetchOldest();
        expect(oldest, isNull);

        // Verify metadata is cleared
        final seqNum = await queue.getLastSequenceNumber('session1');
        expect(seqNum, -1);
      } finally {
        await queue.dispose();
        await dir.delete(recursive: true);
      }
    });
  });
}

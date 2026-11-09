import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/storage/sqlite_event_queue.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session_event.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

import 'helpers/event_queue_contract_tests.dart';

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

      assertUninitializedState(storage);

      await tempDir.delete(recursive: true);
    });
  });

  group('SqliteEventQueue', () {
    late SqliteEventQueue storage;
    late Directory tempDir;

    setUp(() async {
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

    // Shared contract tests (identical assertions for all EventQueue impls)
    runEventQueueContractTests(() => storage);

    test('should keep another user out of a batch when their event is added '
        'while the batch is read', () async {
      // GIVEN a session holding events for user-1
      SessionReplayEvent eventFor(String distinctId, int ms) =>
          SessionReplayEvent(
            sessionId: 'session',
            distinctId: distinctId,
            timestamp: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
            type: EventType.interaction,
            payload: InteractionPayload(interactionType: 7, x: 1, y: 2),
          );
      await storage.add(eventFor('user-1', 1));
      await storage.add(eventFor('user-1', 2));

      // WHEN identify moves recording to user-2 while user-1's batch is
      // being read: the insert is queued behind the boundary query but
      // ahead of the queries that select the batch
      final adding = storage.add(eventFor('user-2', 3));
      final batch = await storage.fetchBatch(
        sessionId: 'session',
        distinctId: 'user-1',
        maxBytes: 1 << 20,
        maxCount: 100,
      );
      await adding;

      // THEN the batch holds only user-1's events
      expect(batch.map((event) => event.distinctId), ['user-1', 'user-1']);
    });

    test('should not skip another user\'s earlier event when both users add '
        'events while the batch is read', () async {
      // GIVEN a session holding events for user-1
      SessionReplayEvent eventFor(String distinctId, int ms) =>
          SessionReplayEvent(
            sessionId: 'session',
            distinctId: distinctId,
            timestamp: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
            type: EventType.interaction,
            payload: InteractionPayload(interactionType: 7, x: 1, y: 2),
          );
      await storage.add(eventFor('user-1', 1));
      await storage.add(eventFor('user-1', 2));

      // WHEN user-2 and then user-1 again record while user-1's batch is
      // being read
      final addingUser2 = storage.add(eventFor('user-2', 3));
      final addingUser1 = storage.add(eventFor('user-1', 4));
      final batch = await storage.fetchBatch(
        sessionId: 'session',
        distinctId: 'user-1',
        maxBytes: 1 << 20,
        maxCount: 100,
      );
      await Future.wait([addingUser2, addingUser1]);

      // THEN the batch stops before user-2's event rather than jumping
      // ahead to user-1's later one, keeping upload order
      expect(batch.map((event) => event.timestamp.millisecondsSinceEpoch), [
        1,
        2,
      ]);
    });

    runQuotaEnforcementTests(() async {
      final quotaDir = await Directory.systemTemp.createTemp('mixpanel_quota_');
      final quotaStorage = SqliteEventQueue(
        token: 'test-token',
        storageDir: quotaDir,
        quotaMB: 1,
        logger: MixpanelLogger(LogLevel.none),
      );
      await quotaStorage.initialize();
      return quotaStorage;
    });
  });
}

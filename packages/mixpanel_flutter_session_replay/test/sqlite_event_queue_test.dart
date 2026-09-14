import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/storage/sqlite_event_queue.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
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

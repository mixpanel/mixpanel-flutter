@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/storage/indexed_db_event_queue.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session_event.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:web/web.dart' as web;

import 'helpers/event_queue_contract_tests.dart';

/// Compute the DB name that [IndexedDbEventQueue] uses for a given token.
String _dbNameForToken(String token) =>
    'mixpanel_replay_${token.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';

/// Delete an IndexedDB database by name (for test cleanup).
Future<void> _deleteDatabase(String name) {
  final completer = Completer<void>();
  final request = web.window.indexedDB.deleteDatabase(name);
  request.onsuccess = (web.Event event) {
    completer.complete();
  }.toJS;
  request.onerror = (web.Event event) {
    completer.complete(); // Best effort
  }.toJS;
  return completer.future;
}

Future<void> _createVersionTwoDatabase(String name) {
  final completer = Completer<void>();
  final request = web.window.indexedDB.open(name, 2);
  request.onupgradeneeded = (web.IDBVersionChangeEvent event) {
    final db = (event.target as web.IDBRequest).result as web.IDBDatabase;
    final events = db.createObjectStore(
      'events',
      web.IDBObjectStoreParameters(keyPath: 'id'.toJS, autoIncrement: true),
    );
    events.createIndex('by_session', 'session_id'.toJS);
    events.put(
      <String, dynamic>{
        'session_id': 'legacy-session',
        'distinct_id': 'legacy-user',
        'timestamp': 500,
        'type': EventType.interaction.index,
        'payload_metadata': '{"type":1,"x":0.0,"y":0.0}',
        'payload_binary': null,
        'data_size': 32,
      }.jsify()!,
    );
    final metadata = db.createObjectStore(
      'session_metadata',
      web.IDBObjectStoreParameters(keyPath: 'session_id'.toJS),
    );
    metadata.put(
      <String, dynamic>{
        'session_id': 'legacy-session',
        'last_sequence_number': 2,
        'session_start_time': 1000,
      }.jsify()!,
    );
    db.createObjectStore(
      'coordination',
      web.IDBObjectStoreParameters(keyPath: 'name'.toJS),
    );
  }.toJS;
  request.onsuccess = (web.Event event) {
    ((event.target as web.IDBRequest).result as web.IDBDatabase).close();
    completer.complete();
  }.toJS;
  request.onerror = (web.Event event) {
    completer.completeError(StateError('Failed to create version 2 database'));
  }.toJS;
  return completer.future;
}

void main() {
  group('Database Naming', () {
    test('initializes database with sanitized token name', () async {
      final token = 'my-project-token';
      final storage = IndexedDbEventQueue(
        token: token,
        logger: MixpanelLogger(LogLevel.none),
      );
      await storage.initialize();

      // Verify the queue is usable (implicitly tests database creation)
      final oldest = await storage.fetchOldest();
      expect(oldest, isNull);

      await storage.dispose();
      await _deleteDatabase(_dbNameForToken(token));
    });

    test('sanitizes special characters in token for database name', () async {
      final token = 'token/with@special!chars';
      final storage = IndexedDbEventQueue(
        token: token,
        logger: MixpanelLogger(LogLevel.none),
      );
      await storage.initialize();

      // Verify the queue is usable with sanitized name
      final oldest = await storage.fetchOldest();
      expect(oldest, isNull);

      await storage.dispose();
      await _deleteDatabase(_dbNameForToken(token));
    });

    test('upgrades version 2 metadata with the start-time index', () async {
      const token = 'version-two-upgrade';
      final dbName = _dbNameForToken(token);
      await _createVersionTwoDatabase(dbName);

      final storage = IndexedDbEventQueue(
        token: token,
        logger: MixpanelLogger(LogLevel.none),
      );
      await storage.initialize();

      final latest = await storage.getLatestSessionMetadata();
      expect(latest?['session_id'], 'legacy-session');
      expect(latest?['last_sequence_number'], 2);

      final oldest = await storage.fetchOldestHeader();
      expect(oldest?.sessionId, 'legacy-session');
      expect(oldest?.distinctId, 'legacy-user');
      expect(oldest?.timestamp.millisecondsSinceEpoch, 500);

      await storage.dispose();
      await _deleteDatabase(dbName);
    });
  });

  group('Uninitialized State', () {
    test('throws StateError when calling methods before initialize', () {
      final storage = IndexedDbEventQueue(
        token: 'test-token-uninit',
        logger: MixpanelLogger(LogLevel.none),
      );

      assertUninitializedState(storage);
    });
  });

  group('IndexedDbEventQueue', () {
    late IndexedDbEventQueue storage;
    final token = 'test-token';

    setUp(() async {
      storage = IndexedDbEventQueue(
        token: token,
        logger: MixpanelLogger(LogLevel.none),
      );
      await storage.initialize();
    });

    tearDown(() async {
      await storage.dispose();
      await _deleteDatabase(_dbNameForToken(token));
    });

    // Shared contract tests (identical assertions for all EventQueue impls)
    runEventQueueContractTests(() => storage);

    group('Session Expiry Methods', () {
      test('updateSessionExpiry stores expiry timestamps', () async {
        final session = Session(
          id: 'session1',
          startTime: DateTime.fromMillisecondsSinceEpoch(1000000, isUtc: true),
          status: SessionStatus.active,
        );
        await storage.createSessionMetadata(session);

        await storage.updateSessionExpiry(
          sessionId: 'session1',
          idleExpiresMs: 5000000,
          maxExpiresMs: 9000000,
        );

        final metadata = await storage.getLatestSessionMetadata();
        expect(metadata, isNotNull);
        expect(metadata!['session_id'], 'session1');
        expect(metadata['idle_expires'], 5000000);
        expect(metadata['max_expires'], 9000000);
      });

      test('updateSessionExpiry is no-op for non-existent session', () async {
        // Should not throw
        await storage.updateSessionExpiry(
          sessionId: 'non-existent',
          idleExpiresMs: 5000000,
          maxExpiresMs: 9000000,
        );

        final metadata = await storage.getLatestSessionMetadata();
        expect(metadata, isNull);
      });

      test('updateSessionExpiry overwrites previous expiry', () async {
        final session = Session(
          id: 'session1',
          startTime: DateTime.fromMillisecondsSinceEpoch(1000000, isUtc: true),
          status: SessionStatus.active,
        );
        await storage.createSessionMetadata(session);

        await storage.updateSessionExpiry(
          sessionId: 'session1',
          idleExpiresMs: 5000000,
          maxExpiresMs: 9000000,
        );
        await storage.updateSessionExpiry(
          sessionId: 'session1',
          idleExpiresMs: 7000000,
          maxExpiresMs: 12000000,
        );

        final metadata = await storage.getLatestSessionMetadata();
        expect(metadata!['idle_expires'], 7000000);
        expect(metadata['max_expires'], 12000000);
      });

      test('getLatestSessionMetadata returns null when empty', () async {
        final metadata = await storage.getLatestSessionMetadata();
        expect(metadata, isNull);
      });

      test(
        'getLatestSessionMetadata returns session with highest start time',
        () async {
          final older = Session(
            id: 'session-old',
            startTime: DateTime.fromMillisecondsSinceEpoch(
              1000000,
              isUtc: true,
            ),
            status: SessionStatus.active,
          );
          final newer = Session(
            id: 'session-new',
            startTime: DateTime.fromMillisecondsSinceEpoch(
              2000000,
              isUtc: true,
            ),
            status: SessionStatus.active,
          );

          // Insert older first, then newer
          await storage.createSessionMetadata(older);
          await storage.createSessionMetadata(newer);

          final metadata = await storage.getLatestSessionMetadata();
          expect(metadata, isNotNull);
          expect(metadata!['session_id'], 'session-new');
          expect(metadata['session_start_time'], 2000000);
        },
      );

      test('getLatestSessionMetadata includes all fields', () async {
        final session = Session(
          id: 'session1',
          startTime: DateTime.fromMillisecondsSinceEpoch(1000000, isUtc: true),
          status: SessionStatus.active,
        );
        await storage.createSessionMetadata(session);
        await storage.updateSequenceNumber('session1', 42);
        await storage.updateSessionExpiry(
          sessionId: 'session1',
          idleExpiresMs: 5000000,
          maxExpiresMs: 9000000,
        );

        final metadata = await storage.getLatestSessionMetadata();
        expect(metadata, isNotNull);
        expect(metadata!['session_id'], 'session1');
        expect(metadata['session_start_time'], 1000000);
        expect(metadata['last_sequence_number'], 42);
        expect(metadata['idle_expires'], 5000000);
        expect(metadata['max_expires'], 9000000);
      });
    });

    group('Cross-tab upload lease', () {
      test('allows only one queue instance to own the lease', () async {
        final secondTab = IndexedDbEventQueue(
          token: token,
          logger: MixpanelLogger(LogLevel.none),
        );
        await secondTab.initialize();
        addTearDown(secondTab.dispose);

        expect(
          await storage.acquireUploadLease(
            ownerId: 'tab-1',
            ttl: const Duration(minutes: 1),
          ),
          isTrue,
        );
        expect(
          await secondTab.acquireUploadLease(
            ownerId: 'tab-2',
            ttl: const Duration(minutes: 1),
          ),
          isFalse,
        );

        await storage.releaseUploadLease(ownerId: 'tab-1');

        expect(
          await secondTab.acquireUploadLease(
            ownerId: 'tab-2',
            ttl: const Duration(minutes: 1),
          ),
          isTrue,
        );
      });

      test(
        'expired lease can be taken over by another queue instance',
        () async {
          final secondTab = IndexedDbEventQueue(
            token: token,
            logger: MixpanelLogger(LogLevel.none),
          );
          await secondTab.initialize();
          addTearDown(secondTab.dispose);

          expect(
            await storage.acquireUploadLease(
              ownerId: 'stale-tab',
              ttl: Duration.zero,
            ),
            isTrue,
          );
          expect(
            await secondTab.acquireUploadLease(
              ownerId: 'replacement-tab',
              ttl: const Duration(minutes: 1),
            ),
            isTrue,
          );
        },
      );
    });

    test('enforces quota across concurrently open tabs', () async {
      final quotaToken = 'cross-tab-quota';
      final firstTab = IndexedDbEventQueue(
        token: quotaToken,
        quotaMB: 1,
        logger: MixpanelLogger(LogLevel.none),
      );
      final secondTab = IndexedDbEventQueue(
        token: quotaToken,
        quotaMB: 1,
        logger: MixpanelLogger(LogLevel.none),
      );
      await firstTab.initialize();
      await secondTab.initialize();
      addTearDown(firstTab.dispose);
      addTearDown(secondTab.dispose);
      addTearDown(() => _deleteDatabase(_dbNameForToken(quotaToken)));

      SessionReplayEvent screenshot(int timestamp) => SessionReplayEvent(
        sessionId: 'session1',
        distinctId: 'user1',
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
        type: EventType.screenshot,
        payload: ScreenshotPayload(imageData: Uint8List(600000)),
      );

      await firstTab.add(screenshot(100));
      await secondTab.add(screenshot(200));

      final stored = await firstTab.fetchBatch(
        sessionId: 'session1',
        distinctId: 'user1',
        maxBytes: 5000000,
        maxCount: 100,
      );
      expect(stored, hasLength(1));
      expect(stored.single.timestamp.millisecondsSinceEpoch, 100);
    });

    test('persists events and metadata after closing and reopening', () async {
      const reopenToken = 'reopen-persistence';
      final first = IndexedDbEventQueue(
        token: reopenToken,
        logger: MixpanelLogger(LogLevel.none),
      );
      await first.initialize();
      await first.createSessionMetadata(
        Session(
          id: 'session1',
          startTime: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
          status: SessionStatus.active,
        ),
      );
      await first.updateSequenceNumber('session1', 3);
      await first.add(
        SessionReplayEvent(
          sessionId: 'session1',
          distinctId: 'user1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
          type: EventType.screenshot,
          payload: ScreenshotPayload(
            imageData: Uint8List.fromList(<int>[1, 2, 3]),
          ),
        ),
      );
      await first.dispose();

      final reopened = IndexedDbEventQueue(
        token: reopenToken,
        logger: MixpanelLogger(LogLevel.none),
      );
      await reopened.initialize();
      addTearDown(reopened.dispose);
      addTearDown(() => _deleteDatabase(_dbNameForToken(reopenToken)));

      expect(await reopened.getLastSequenceNumber('session1'), 3);
      expect(
        (await reopened.getSessionMetadata(
          'session1',
        ))?.startTime.millisecondsSinceEpoch,
        1000,
      );
      final event = await reopened.fetchOldest();
      expect(event, isNotNull);
      expect((event!.payload as ScreenshotPayload).imageData, <int>[1, 2, 3]);
    });

    test(
      'atomically removes an uploaded batch and advances its sequence',
      () async {
        const sessionId = 'atomic-session';
        await storage.createSessionMetadata(
          Session(
            id: sessionId,
            startTime: DateTime.utc(2025),
            status: SessionStatus.active,
          ),
        );
        await storage.add(
          SessionReplayEvent(
            sessionId: sessionId,
            distinctId: 'user-1',
            timestamp: DateTime.utc(2025),
            type: EventType.interaction,
            payload: InteractionPayload(interactionType: 1, x: 10, y: 20),
          ),
        );
        final batch = await storage.fetchBatch(
          sessionId: sessionId,
          distinctId: 'user-1',
          maxBytes: 1024,
          maxCount: 10,
        );

        await storage.commitUploadedBatch(
          events: batch,
          sessionId: sessionId,
          sequenceNumber: 4,
        );

        expect(await storage.fetchOldest(), isNull);
        expect(await storage.getLastSequenceNumber(sessionId), 4);
      },
    );

    test('a stale commit never moves the sequence number backwards', () async {
      // GIVEN a session another tab already advanced to sequence 5
      const sessionId = 'stale-commit-session';
      await storage.createSessionMetadata(
        Session(
          id: sessionId,
          startTime: DateTime.utc(2025),
          status: SessionStatus.active,
        ),
      );
      await storage.add(
        SessionReplayEvent(
          sessionId: sessionId,
          distinctId: 'user-1',
          timestamp: DateTime.utc(2025),
          type: EventType.interaction,
          payload: InteractionPayload(interactionType: 1, x: 10, y: 20),
        ),
      );
      final batch = await storage.fetchBatch(
        sessionId: sessionId,
        distinctId: 'user-1',
        maxBytes: 1024,
        maxCount: 10,
      );
      await storage.updateSequenceNumber(sessionId, 5);

      // WHEN a tab whose lease expired commits an older sequence number
      await storage.commitUploadedBatch(
        events: batch,
        sessionId: sessionId,
        sequenceNumber: 4,
      );

      // THEN the batch is removed but the newer sequence number is kept
      expect(await storage.fetchOldest(), isNull);
      expect(await storage.getLastSequenceNumber(sessionId), 5);
    });

    test(
      'rolls back batch deletion when session metadata is missing',
      () async {
        await storage.add(
          SessionReplayEvent(
            sessionId: 'missing-metadata',
            distinctId: 'user-1',
            timestamp: DateTime.utc(2025),
            type: EventType.interaction,
            payload: InteractionPayload(interactionType: 1, x: 10, y: 20),
          ),
        );
        final batch = await storage.fetchBatch(
          sessionId: 'missing-metadata',
          distinctId: 'user-1',
          maxBytes: 1024,
          maxCount: 10,
        );

        await expectLater(
          storage.commitUploadedBatch(
            events: batch,
            sessionId: 'missing-metadata',
            sequenceNumber: 4,
          ),
          throwsStateError,
        );

        expect(await storage.fetchOldest(), isNotNull);
        expect(await storage.getLastSequenceNumber('missing-metadata'), -1);
      },
    );

    test(
      'prunes expired events and only unreferenced old session metadata',
      () async {
        final cutoff = DateTime.utc(2026, 1, 10);
        final expiredSession = Session(
          id: 'expired-session',
          startTime: DateTime.utc(2026, 1, 1),
          status: SessionStatus.ended,
        );
        final activeSession = Session(
          id: 'active-session',
          startTime: DateTime.utc(2026, 1, 1),
          status: SessionStatus.active,
        );
        await storage.createSessionMetadata(expiredSession);
        await storage.createSessionMetadata(activeSession);

        for (final event in <SessionReplayEvent>[
          SessionReplayEvent(
            sessionId: expiredSession.id,
            distinctId: 'user-1',
            timestamp: DateTime.utc(2026, 1, 2),
            type: EventType.screenshot,
            payload: ScreenshotPayload(imageData: Uint8List(1024)),
          ),
          SessionReplayEvent(
            sessionId: activeSession.id,
            distinctId: 'user-1',
            timestamp: DateTime.utc(2026, 1, 3),
            type: EventType.interaction,
            payload: InteractionPayload(interactionType: 1, x: 1, y: 2),
          ),
          SessionReplayEvent(
            sessionId: activeSession.id,
            distinctId: 'user-1',
            timestamp: DateTime.utc(2026, 1, 11),
            type: EventType.interaction,
            payload: InteractionPayload(interactionType: 2, x: 3, y: 4),
          ),
        ]) {
          await storage.add(event);
        }

        final result = await storage.pruneExpiredData(cutoff);

        expect(result.removedEvents, 2);
        expect(result.removedSessions, 1);
        expect(await storage.getSessionMetadata(expiredSession.id), isNull);
        expect(await storage.getSessionMetadata(activeSession.id), isNotNull);
        final remaining = await storage.fetchBatch(
          sessionId: activeSession.id,
          distinctId: 'user-1',
          maxBytes: 1024,
          maxCount: 10,
        );
        expect(remaining, hasLength(1));
        expect(remaining.single.timestamp, DateTime.utc(2026, 1, 11));
      },
    );

    runQuotaEnforcementTests(() async {
      final quotaToken = 'test-token-quota';
      final quotaStorage = IndexedDbEventQueue(
        token: quotaToken,
        quotaMB: 1,
        logger: MixpanelLogger(LogLevel.none),
      );
      await quotaStorage.initialize();
      addTearDown(() => _deleteDatabase(_dbNameForToken(quotaToken)));
      return quotaStorage;
    });
  });
}

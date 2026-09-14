@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/storage/indexed_db_event_queue.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session/web_session_resume.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:web/web.dart' as web;

String _dbNameForToken(String token) =>
    'mixpanel_replay_${token.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';

Future<void> _deleteDatabase(String name) {
  final completer = Completer<void>();
  final request = web.window.indexedDB.deleteDatabase(name);
  request.onsuccess = (web.Event event) {
    completer.complete();
  }.toJS;
  request.onerror = (web.Event event) {
    completer.complete();
  }.toJS;
  return completer.future;
}

void main() {
  late IndexedDbEventQueue queue;
  late MixpanelLogger logger;
  final token = 'test-token-resume';

  setUp(() async {
    logger = MixpanelLogger(LogLevel.none);
    queue = IndexedDbEventQueue(token: token, logger: logger);
    await queue.initialize();
  });

  tearDown(() async {
    await queue.dispose();
    await _deleteDatabase(_dbNameForToken(token));
  });

  group('checkWebSessionResume', () {
    test('returns null when no sessions exist', () async {
      final result = await checkWebSessionResume(
        queue: queue,
        idleTimeout: const Duration(minutes: 30),
        maxSessionDuration: const Duration(hours: 24),
        logger: logger,
      );

      expect(result, isNull);
    });

    test('returns session info for valid non-expired session', () async {
      final session = Session(
        id: 'session-abc',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000000, isUtc: true),
        status: SessionStatus.active,
      );
      await queue.createSessionMetadata(session);
      await queue.updateSequenceNumber('session-abc', 7);

      // Set expiry far in the future
      final futureMs = DateTime.now().millisecondsSinceEpoch + 3600000;
      await queue.updateSessionExpiry(
        sessionId: 'session-abc',
        idleExpiresMs: futureMs,
        maxExpiresMs: futureMs,
      );

      final result = await checkWebSessionResume(
        queue: queue,
        idleTimeout: const Duration(minutes: 30),
        maxSessionDuration: const Duration(hours: 24),
        logger: logger,
      );

      expect(result, isNotNull);
      expect(result!.session.id, 'session-abc');
      expect(result.session.startTime.millisecondsSinceEpoch, 1000000);
      expect(result.lastSequenceNumber, 7);
    });

    test('returns null when max duration exceeded', () async {
      final session = Session(
        id: 'session-expired',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000000, isUtc: true),
        status: SessionStatus.active,
      );
      await queue.createSessionMetadata(session);

      // Set max_expires in the past
      final pastMs = DateTime.now().millisecondsSinceEpoch - 1000;
      await queue.updateSessionExpiry(
        sessionId: 'session-expired',
        idleExpiresMs: DateTime.now().millisecondsSinceEpoch + 3600000,
        maxExpiresMs: pastMs,
      );

      final result = await checkWebSessionResume(
        queue: queue,
        idleTimeout: const Duration(minutes: 30),
        maxSessionDuration: const Duration(hours: 24),
        logger: logger,
      );

      expect(result, isNull);
    });

    test('returns null when idle timeout exceeded', () async {
      final session = Session(
        id: 'session-idle',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000000, isUtc: true),
        status: SessionStatus.active,
      );
      await queue.createSessionMetadata(session);

      // Set idle_expires in the past, max_expires in the future
      final pastMs = DateTime.now().millisecondsSinceEpoch - 1000;
      final futureMs = DateTime.now().millisecondsSinceEpoch + 3600000;
      await queue.updateSessionExpiry(
        sessionId: 'session-idle',
        idleExpiresMs: pastMs,
        maxExpiresMs: futureMs,
      );

      final result = await checkWebSessionResume(
        queue: queue,
        idleTimeout: const Duration(minutes: 30),
        maxSessionDuration: const Duration(hours: 24),
        logger: logger,
      );

      expect(result, isNull);
    });

    test(
      'returns session for legacy session (no expiry data) within max duration',
      () async {
        // Legacy session: has metadata but no idle_expires/max_expires
        final recentStartMs =
            DateTime.now().millisecondsSinceEpoch - 60000; // 1 min ago
        final session = Session(
          id: 'session-legacy',
          startTime: DateTime.fromMillisecondsSinceEpoch(
            recentStartMs,
            isUtc: true,
          ),
          status: SessionStatus.active,
        );
        await queue.createSessionMetadata(session);
        // No updateSessionExpiry call — simulates legacy session

        final result = await checkWebSessionResume(
          queue: queue,
          idleTimeout: const Duration(minutes: 30),
          maxSessionDuration: const Duration(hours: 24),
          logger: logger,
        );

        expect(result, isNotNull);
        expect(result!.session.id, 'session-legacy');
      },
    );

    test('returns null for legacy session exceeding max duration', () async {
      // Legacy session started long ago
      final oldStartMs =
          DateTime.now().millisecondsSinceEpoch -
          const Duration(hours: 25).inMilliseconds;
      final session = Session(
        id: 'session-old-legacy',
        startTime: DateTime.fromMillisecondsSinceEpoch(oldStartMs, isUtc: true),
        status: SessionStatus.active,
      );
      await queue.createSessionMetadata(session);

      final result = await checkWebSessionResume(
        queue: queue,
        idleTimeout: const Duration(minutes: 30),
        maxSessionDuration: const Duration(hours: 24),
        logger: logger,
      );

      expect(result, isNull);
    });

    test('resumes the latest session when multiple exist', () async {
      final older = Session(
        id: 'session-old',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000000, isUtc: true),
        status: SessionStatus.active,
      );
      final newer = Session(
        id: 'session-new',
        startTime: DateTime.fromMillisecondsSinceEpoch(2000000, isUtc: true),
        status: SessionStatus.active,
      );
      await queue.createSessionMetadata(older);
      await queue.createSessionMetadata(newer);
      await queue.updateSequenceNumber('session-new', 3);

      // Set valid expiry on the newer session
      final futureMs = DateTime.now().millisecondsSinceEpoch + 3600000;
      await queue.updateSessionExpiry(
        sessionId: 'session-new',
        idleExpiresMs: futureMs,
        maxExpiresMs: futureMs,
      );

      final result = await checkWebSessionResume(
        queue: queue,
        idleTimeout: const Duration(minutes: 30),
        maxSessionDuration: const Duration(hours: 24),
        logger: logger,
      );

      expect(result, isNotNull);
      expect(result!.session.id, 'session-new');
      expect(result.lastSequenceNumber, 3);
    });

    test('defaults lastSequenceNumber to -1 when not set', () async {
      final session = Session(
        id: 'session-noseq',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000000, isUtc: true),
        status: SessionStatus.active,
      );
      await queue.createSessionMetadata(session);

      final futureMs = DateTime.now().millisecondsSinceEpoch + 3600000;
      await queue.updateSessionExpiry(
        sessionId: 'session-noseq',
        idleExpiresMs: futureMs,
        maxExpiresMs: futureMs,
      );

      final result = await checkWebSessionResume(
        queue: queue,
        idleTimeout: const Duration(minutes: 30),
        maxSessionDuration: const Duration(hours: 24),
        logger: logger,
      );

      expect(result, isNotNull);
      expect(result!.lastSequenceNumber, -1);
    });

    test('does not resume a session owned by another browser tab', () async {
      final ownedQueue = IndexedDbEventQueue(
        token: token,
        ownerId: 'tab-1',
        logger: logger,
      );
      await queue.dispose();
      queue = ownedQueue;
      await queue.initialize();
      final session = Session(
        id: 'session-tab-1',
        startTime: DateTime.now().toUtc(),
        status: SessionStatus.active,
      );
      await queue.createSessionMetadata(session);
      final futureMs = DateTime.now().millisecondsSinceEpoch + 3600000;
      await queue.updateSessionExpiry(
        sessionId: session.id,
        idleExpiresMs: futureMs,
        maxExpiresMs: futureMs,
      );

      final otherTab = IndexedDbEventQueue(
        token: token,
        ownerId: 'tab-2',
        logger: logger,
      );
      await otherTab.initialize();

      final result = await checkWebSessionResume(
        queue: otherTab,
        idleTimeout: const Duration(minutes: 30),
        maxSessionDuration: const Duration(hours: 24),
        logger: logger,
      );

      expect(result, isNull);
      await otherTab.dispose();
    });

    test('resumes after reload when tab ownership is unchanged', () async {
      final firstPage = IndexedDbEventQueue(
        token: token,
        ownerId: 'stable-tab',
        logger: logger,
      );
      await queue.dispose();
      queue = firstPage;
      await queue.initialize();
      final session = Session(
        id: 'session-reload',
        startTime: DateTime.now().toUtc(),
        status: SessionStatus.active,
      );
      await queue.createSessionMetadata(session);
      final futureMs = DateTime.now().millisecondsSinceEpoch + 3600000;
      await queue.updateSessionExpiry(
        sessionId: session.id,
        idleExpiresMs: futureMs,
        maxExpiresMs: futureMs,
      );
      await queue.dispose();

      queue = IndexedDbEventQueue(
        token: token,
        ownerId: 'stable-tab',
        logger: logger,
      );
      await queue.initialize();

      final result = await checkWebSessionResume(
        queue: queue,
        idleTimeout: const Duration(minutes: 30),
        maxSessionDuration: const Duration(hours: 24),
        logger: logger,
      );

      expect(result?.session.id, session.id);
    });
  });

  group('updateWebSessionExpiry', () {
    test(
      'persists expiry timestamps readable by checkWebSessionResume',
      () async {
        final session = Session(
          id: 'session-roundtrip',
          startTime: DateTime.fromMillisecondsSinceEpoch(1000000, isUtc: true),
          status: SessionStatus.active,
        );
        await queue.createSessionMetadata(session);

        final futureMs = DateTime.now().millisecondsSinceEpoch + 3600000;
        await updateWebSessionExpiry(
          queue: queue,
          sessionId: 'session-roundtrip',
          idleExpiresMs: futureMs,
          maxExpiresMs: futureMs,
          logger: logger,
        );

        // Verify the expiry is readable and session is resumable
        final result = await checkWebSessionResume(
          queue: queue,
          idleTimeout: const Duration(minutes: 30),
          maxSessionDuration: const Duration(hours: 24),
          logger: logger,
        );

        expect(result, isNotNull);
        expect(result!.session.id, 'session-roundtrip');
      },
    );
  });
}

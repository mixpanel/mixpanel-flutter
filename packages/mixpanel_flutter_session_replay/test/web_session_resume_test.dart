@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/storage/indexed_db_event_queue.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session/web_session_resume.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session_event.dart';
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
    test(
      'rejects an expired background deadline after reopening storage',
      () async {
        // GIVEN a replay with valid activity/max deadlines but expired background retention.
        final now = DateTime.now();
        final ownerId = queue.ownerId;
        await queue.createSessionMetadata(
          Session(
            id: 'background-expired',
            startTime: now,
            status: SessionStatus.active,
          ),
        );
        await updateWebSessionExpiry(
          queue: queue,
          sessionId: 'background-expired',
          idleExpiresMs: now
              .add(const Duration(minutes: 30))
              .millisecondsSinceEpoch,
          maxExpiresMs: now
              .add(const Duration(hours: 24))
              .millisecondsSinceEpoch,
          backgroundExpiresMs: now
              .subtract(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
          logger: logger,
        );

        // WHEN a new page opens the same tab's persistent queue.
        await queue.dispose();
        queue = IndexedDbEventQueue(
          token: token,
          logger: logger,
          ownerId: ownerId,
        );
        await queue.initialize();
        final result = await checkWebSessionResume(
          queue: queue,
          maxSessionDuration: const Duration(hours: 24),
          logger: logger,
        );

        // THEN the old replay cannot resume even though activity idle has not expired.
        expect(result, isNull);
      },
    );

    test(
      'returns background expiry for revalidation and clears it on foreground',
      () async {
        final now = DateTime.now();
        final idle = now
            .add(const Duration(minutes: 30))
            .millisecondsSinceEpoch;
        final max = now.add(const Duration(hours: 24)).millisecondsSinceEpoch;
        final background = now
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch;
        await queue.createSessionMetadata(
          Session(
            id: 'background-valid',
            startTime: now,
            status: SessionStatus.active,
          ),
        );
        await updateWebSessionExpiry(
          queue: queue,
          sessionId: 'background-valid',
          idleExpiresMs: idle,
          maxExpiresMs: max,
          backgroundExpiresMs: background,
          logger: logger,
        );
        final result = await checkWebSessionResume(
          queue: queue,
          maxSessionDuration: const Duration(hours: 24),
          logger: logger,
        );
        expect(result!.backgroundExpiry!.millisecondsSinceEpoch, background);
        expect(result.idleExpiry!.millisecondsSinceEpoch, idle);

        // WHEN foregrounding clears background retention without changing activity idle.
        await updateWebSessionExpiry(
          queue: queue,
          sessionId: 'background-valid',
          idleExpiresMs: idle,
          maxExpiresMs: max,
          backgroundExpiresMs: null,
          logger: logger,
        );
        final metadata = await queue.getLatestSessionMetadata();
        expect(metadata!['background_expires'], isNull);
        expect(metadata['idle_expires'], idle);
        expect(metadata['max_expires'], max);
      },
    );

    test('returns null when no sessions exist', () async {
      final result = await checkWebSessionResume(
        queue: queue,
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
        maxSessionDuration: const Duration(hours: 24),
        logger: logger,
      );

      expect(result, isNull);
      await otherTab.dispose();
    });

    test('never resumes metadata rebuilt for an orphaned backlog', () async {
      // GIVEN events for a session whose metadata write was lost, then the
      // uploader rebuilding that metadata as an ended session
      await queue.add(
        SessionReplayEvent(
          sessionId: 'orphaned',
          distinctId: 'user-1',
          timestamp: DateTime.now().toUtc(),
          type: EventType.interaction,
          payload: InteractionPayload(interactionType: 1, x: 1, y: 2),
        ),
      );
      await queue.createSessionMetadata(
        Session(
          id: 'orphaned',
          startTime: DateTime.now().toUtc(),
          status: SessionStatus.ended,
        ),
      );
      final otherTab = IndexedDbEventQueue(
        token: token,
        ownerId: 'tab-2',
        logger: logger,
      );
      await otherTab.initialize();
      addTearDown(otherTab.dispose);

      // WHEN either the rebuilding tab or another tab reloads
      final sameTab = await checkWebSessionResume(
        queue: queue,
        maxSessionDuration: const Duration(hours: 24),
        logger: logger,
      );
      final other = await checkWebSessionResume(
        queue: otherTab,
        maxSessionDuration: const Duration(hours: 24),
        logger: logger,
      );

      // THEN the rebuilt session stays uploadable but is not resumed
      expect(sameTab, isNull);
      expect(other, isNull);
      expect((await otherTab.fetchOldestHeader())?.sessionId, 'orphaned');
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
          maxSessionDuration: const Duration(hours: 24),
          logger: logger,
        );

        expect(result, isNotNull);
        expect(result!.session.id, 'session-roundtrip');
      },
    );
  });
}

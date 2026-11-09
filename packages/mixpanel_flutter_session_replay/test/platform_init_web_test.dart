@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/platform/platform_init.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session/replay_lifecycle_policy.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/storage/indexed_db_event_queue.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session_event.dart';

import 'package:web/web.dart' as web;

import 'helpers/in_memory_event_queue.dart';

/// Queue whose resume lookup fails, as it does when a metadata record holds a
/// value this SDK version cannot parse or the read transaction aborts.
class _UnreadableMetadataQueue extends IndexedDbEventQueue {
  _UnreadableMetadataQueue({required super.token, required super.logger});

  @override
  Future<Map<String, dynamic>?> getLatestSessionMetadata({String? ownedBy}) {
    throw StateError('Failed to read latest session metadata');
  }
}

Future<void> _deleteDatabase(String token) {
  final completer = Completer<void>();
  final request = web.window.indexedDB.deleteDatabase(
    'mixpanel_replay_${token.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}',
  );
  request.onsuccess = (web.Event event) {
    completer.complete();
  }.toJS;
  request.onerror = (web.Event event) {
    completer.complete();
  }.toJS;
  return completer.future;
}

void main() {
  test(
    'fails initialization when persistent storage cannot be opened',
    () async {
      // GIVEN a database newer than this SDK can open
      const token = 'unsupported-database-version';
      addTearDown(() => _deleteDatabase(token));
      final opened = Completer<void>();
      final request = web.window.indexedDB.open('mixpanel_replay_$token', 99);
      request.onsuccess = (web.Event event) {
        ((event.target as web.IDBRequest).result as web.IDBDatabase).close();
        opened.complete();
      }.toJS;
      request.onerror = (web.Event event) {
        opened.completeError(StateError('Failed to create test database'));
      }.toJS;
      await opened.future;

      // WHEN the public SDK initializes without an injected test queue
      final result = await MixpanelSessionReplay.initialize(
        token: token,
        distinctId: 'test-user',
      );
      addTearDown(() async => result.instance?.coordinator.dispose());

      // THEN replay is disabled rather than buffering screenshots in RAM
      expect(result.success, isFalse);
      expect(result.error, InitializationError.storageFailure);
      expect(result.instance, isNull);
    },
  );

  test(
    'web initialization preserves queued events when no session can resume',
    () async {
      final queue = InMemoryEventQueue();
      await queue.initialize();
      final session = Session(
        id: 'upload-backlog',
        startTime: DateTime.utc(2025),
        status: SessionStatus.ended,
      );
      await queue.createSessionMetadata(session);
      await queue.add(
        SessionReplayEvent(
          sessionId: session.id,
          distinctId: 'user-1',
          timestamp: DateTime.utc(2025),
          type: EventType.metadata,
          payload: MetadataPayload(width: 100, height: 200),
        ),
      );

      final result = await platformInit(
        token: 'test-token',
        storageQuotaMB: 50,
        directive: MaskingDirective(autoMaskTypes: const {}),
        debugOverlayEnabled: false,
        platformOptions: const PlatformOptions(),
        useAccessibilityLabelFallback: false,
        logger: MixpanelLogger(LogLevel.none),
        eventQueue: queue,
      );

      expect(result.sessionPersistence.takeResumable(), isNull);
      // A hidden page keeps recording, as in mixpanel-js.
      expect(result.lifecyclePolicy, isA<RecordThroughBackground>());
      expect(queue.eventCount, 1);

      await result.screenshotCapturer.dispose();
      result.gzipCompressor.dispose();
      await queue.dispose();
    },
  );

  test('starts fresh when the resumable session cannot be read', () async {
    // GIVEN persistent storage whose session metadata cannot be read
    const token = 'unreadable-resume-token';
    addTearDown(() => _deleteDatabase(token));
    final queue = _UnreadableMetadataQueue(
      token: token,
      logger: MixpanelLogger(LogLevel.none),
    );

    // WHEN the SDK initializes on this page
    final result = await platformInit(
      token: token,
      storageQuotaMB: 50,
      directive: MaskingDirective(autoMaskTypes: const {}),
      debugOverlayEnabled: false,
      platformOptions: const PlatformOptions(),
      useAccessibilityLabelFallback: false,
      logger: MixpanelLogger(LogLevel.none),
      eventQueue: queue,
    );

    // THEN initialization succeeds without a resumed session rather than
    // failing on every page load until the site data is cleared
    expect(result.sessionPersistence.takeResumable(), isNull);
    expect(result.queue, same(queue));

    await result.dispose();
  });
}

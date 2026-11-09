import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/replay_identity.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/settings/settings_service.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/storage/sqlite_event_queue.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/upload/payload_serializer.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/upload/upload_service.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session_event.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/fake_connectivity.dart';
import 'helpers/fake_http_client.dart';
import 'helpers/in_memory_event_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const acme = MixpanelIdentity.withDeviceId(
    userId: 'user_123',
    companyId: 'acme',
    deviceId: 'device_1',
  );

  group('ReplayIdentity', () {
    test('distinct id is the user id once identified', () {
      expect(ReplayIdentity.distinctId(acme), 'user_123');
    });

    test('distinct id is the device id before the user is known', () {
      // GIVEN
      const anonymous = MixpanelIdentity.withDeviceId(
        userId: null,
        deviceId: 'device_1',
      );

      // THEN
      expect(ReplayIdentity.distinctId(anonymous), '\$device:device_1');
    });

    test('distinct id is null without a user id or device id', () {
      // GIVEN
      const companyOnly = MixpanelIdentity.withDeviceId(
        userId: '',
        companyId: 'acme',
        deviceId: '',
      );

      // THEN
      expect(ReplayIdentity.distinctId(companyOnly), isNull);
    });

    test('query params carry every id', () {
      expect(ReplayIdentity.queryParams(acme), {
        '\$user_id': 'user_123',
        '\$company_id': 'acme',
        '\$device_id': 'device_1',
      });
    });

    test('query params leave out empty and missing ids', () {
      // GIVEN
      const identity = MixpanelIdentity(userId: 'user_123', companyId: '');

      // THEN
      expect(ReplayIdentity.queryParams(identity), {'\$user_id': 'user_123'});
      expect(ReplayIdentity.queryParams(null), isEmpty);
    });

    test('a distinct id without an identity is stored as itself', () {
      expect(ReplayIdentity.storedDistinctId('user_123', null), 'user_123');
      expect(ReplayIdentity.fromStoredDistinctId('user_123'), (
        'user_123',
        null,
      ));
    });

    test(
      'a stored identity reads back as the same distinct id and identity',
      () {
        // WHEN
        final stored = ReplayIdentity.storedDistinctId('user_123', acme);

        // THEN
        expect(stored, isNot('user_123'));
        expect(ReplayIdentity.fromStoredDistinctId(stored), ('user_123', acme));
      },
    );

    test('different identities for the same user store differently', () {
      // GIVEN
      const globex = MixpanelIdentity.withDeviceId(
        userId: 'user_123',
        companyId: 'globex',
        deviceId: 'device_1',
      );

      // THEN
      expect(
        ReplayIdentity.storedDistinctId('user_123', acme),
        isNot(ReplayIdentity.storedDistinctId('user_123', globex)),
      );
    });

    test('empty ids store the same as missing ones', () {
      // GIVEN
      const withEmpty = MixpanelIdentity(userId: 'user_123', companyId: '');
      const withoutCompany = MixpanelIdentity(userId: 'user_123');

      // THEN
      expect(
        ReplayIdentity.storedDistinctId('user_123', withEmpty),
        ReplayIdentity.storedDistinctId('user_123', withoutCompany),
      );
    });
  });

  group('MixpanelSessionReplay identity', () {
    const token = 'identity-token';
    const options = SessionReplayOptions(
      logLevel: LogLevel.none,
      flushInterval: Duration(hours: 1),
    );

    Future<(MixpanelSessionReplay, InMemoryEventQueue)> startRecording({
      MixpanelIdentity? identity,
    }) async {
      final queue = InMemoryEventQueue();
      await queue.initialize();
      final result = await MixpanelSessionReplay.initializeWithDependencies(
        token: token,
        distinctId: identity == null
            ? 'plain-user'
            : ReplayIdentity.distinctId(identity)!,
        identity: identity,
        options: options,
        eventQueue: queue,
      );
      final instance = result.instance!;
      instance.startRecording();
      await pumpEventQueue();
      return (instance, queue);
    }

    Future<PersistedSessionReplayEvent> recordTouch(
      MixpanelSessionReplay instance,
      InMemoryEventQueue queue,
    ) async {
      instance.coordinator.captureInteraction(2, Offset.zero, DateTime.now());
      await pumpEventQueue();
      return (await queue.fetchNewest())!;
    }

    test(
      'initializeWithIdentity fails without a user id or device id',
      () async {
        // WHEN
        final result = await MixpanelSessionReplay.initializeWithIdentity(
          token: token,
          identity: const MixpanelIdentity(userId: null, companyId: 'acme'),
          options: options,
        );

        // THEN
        expect(result.success, false);
        expect(result.error, InitializationError.invalidToken);
      },
    );

    test('events carry the identity Session Replay started with', () async {
      // GIVEN
      final (instance, queue) = await startRecording(identity: acme);

      // WHEN
      final event = await recordTouch(instance, queue);

      // THEN
      expect(instance.distinctId, 'user_123');
      expect(event.distinctId, 'user_123');
      expect(event.identity, acme);
    });

    test('identifyWithIdentity applies to later events only', () async {
      // GIVEN
      final (instance, queue) = await startRecording(identity: acme);
      final before = await recordTouch(instance, queue);

      // WHEN
      instance.identifyWithIdentity(
        const MixpanelIdentity(userId: 'user_123', companyId: 'globex'),
      );
      final after = await recordTouch(instance, queue);

      // THEN
      expect(before.identity?.companyId, 'acme');
      expect(after.distinctId, 'user_123');
      expect(after.identity?.companyId, 'globex');
    });

    test(
      'identifyWithIdentity before the user is known uses the device',
      () async {
        // GIVEN
        final (instance, queue) = await startRecording();

        // WHEN
        instance.identifyWithIdentity(
          const MixpanelIdentity.withDeviceId(
            userId: null,
            deviceId: 'device_1',
          ),
        );
        final event = await recordTouch(instance, queue);

        // THEN
        expect(instance.distinctId, '\$device:device_1');
        expect(event.identity?.deviceId, 'device_1');
      },
    );

    test(
      'identifyWithIdentity without a user id or device id is ignored',
      () async {
        // GIVEN
        final (instance, queue) = await startRecording(identity: acme);

        // WHEN
        instance.identifyWithIdentity(
          const MixpanelIdentity(userId: '', companyId: 'globex'),
        );
        final event = await recordTouch(instance, queue);

        // THEN
        expect(instance.distinctId, 'user_123');
        expect(event.identity, acme);
      },
    );

    test('identify with a distinct id drops the identity', () async {
      // GIVEN
      final (instance, queue) = await startRecording(identity: acme);

      // WHEN
      instance.identify('plain-user');
      final event = await recordTouch(instance, queue);

      // THEN
      expect(event.distinctId, 'plain-user');
      expect(event.identity, isNull);
    });

    test('events without an identity carry none', () async {
      // GIVEN
      final (instance, queue) = await startRecording();

      // WHEN
      final event = await recordTouch(instance, queue);

      // THEN
      expect(event.distinctId, 'plain-user');
      expect(event.identity, isNull);
    });
  });

  group('SqliteEventQueue identity', () {
    late Directory tempDir;
    late SqliteEventQueue queue;

    SessionReplayEvent touch(int time, MixpanelIdentity? identity) =>
        SessionReplayEvent(
          sessionId: 'session1',
          distinctId: 'user_123',
          identity: identity,
          timestamp: DateTime.fromMillisecondsSinceEpoch(time, isUtc: true),
          type: EventType.interaction,
          payload: InteractionPayload(interactionType: 1, x: 0, y: 0),
        );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mixpanel_test_');
      queue = SqliteEventQueue(
        token: 'test-token',
        storageDir: tempDir,
        logger: MixpanelLogger(LogLevel.none),
      );
    });

    tearDown(() async {
      await queue.dispose();
      await tempDir.delete(recursive: true);
    });

    test('stores the identity with each event', () async {
      // GIVEN
      await queue.initialize();

      // WHEN
      await queue.add(touch(100, acme));

      // THEN
      final event = (await queue.fetchOldest())!;
      expect(event.distinctId, 'user_123');
      expect(event.identity, acme);
    });

    test('identity events upload with their ids beside distinct_id', () async {
      // GIVEN
      await queue.initialize();
      final session = Session(
        id: 'session1',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
        status: SessionStatus.active,
      );
      await queue.createSessionMetadata(session);
      const globex = MixpanelIdentity(userId: 'user_123', companyId: 'globex');
      await queue.add(touch(100, acme));
      await queue.add(touch(200, globex));
      await queue.add(touch(300, null));
      final recorder = createRecordingHttpClient(statusCode: 200);
      final service = UploadService(
        eventQueue: queue,
        payloadSerializer: PayloadSerializer('test-token'),
        wifiOnly: false,
        getRemoteEnablementState: () => RemoteEnablementState.enabled,
        flushInterval: const Duration(seconds: 10),
        logger: MixpanelLogger(LogLevel.none),
        httpClient: recorder.client,
        connectivity: FakeConnectivity([ConnectivityResult.wifi]),
      );

      // WHEN
      await service.flush();

      // THEN
      final params = recorder.requests
          .map((r) => r.url.queryParameters)
          .toList();
      expect(params.map((p) => p['distinct_id']), [
        'user_123',
        'user_123',
        'user_123',
      ]);
      expect(params.map((p) => p['\$user_id']), ['user_123', 'user_123', null]);
      expect(params.map((p) => p['\$company_id']), ['acme', 'globex', null]);
      expect(params.map((p) => p['\$device_id']), ['device_1', null, null]);
      expect(await queue.fetchOldest(), isNull);
    });

    test('a batch stops where the company changes for the same user', () async {
      // GIVEN
      await queue.initialize();
      const globex = MixpanelIdentity(userId: 'user_123', companyId: 'globex');
      await queue.add(touch(100, acme));
      await queue.add(touch(200, acme));
      await queue.add(touch(300, globex));

      // WHEN
      final oldest = (await queue.fetchOldest())!;
      final batch = await queue.fetchBatch(
        sessionId: oldest.sessionId,
        distinctId: oldest.distinctId,
        identity: oldest.identity,
        maxBytes: 5000000,
        maxCount: 100,
      );

      // THEN
      expect(batch.map((e) => e.timestamp.millisecondsSinceEpoch), [100, 200]);
    });

    test(
      'a batch stops where an identity starts after events without one',
      () async {
        // GIVEN
        await queue.initialize();
        await queue.add(touch(100, null));
        await queue.add(touch(200, acme));

        // WHEN
        final batch = await queue.fetchBatch(
          sessionId: 'session1',
          distinctId: 'user_123',
          maxBytes: 5000000,
          maxCount: 100,
        );

        // THEN
        expect(batch.map((e) => e.timestamp.millisecondsSinceEpoch), [100]);
      },
    );

    test('an event without an identity stores its plain distinct id', () async {
      // GIVEN
      await queue.initialize();

      // WHEN
      await queue.add(touch(100, null));

      // THEN
      final event = (await queue.fetchOldest())!;
      expect(event.distinctId, 'user_123');
      expect(event.identity, isNull);
      await queue.dispose();
      final db = await databaseFactoryFfi.openDatabase(
        '${tempDir.path}/mixpanel_replay_test-token.db',
      );
      expect(await db.getVersion(), 1);
      expect(await db.query('events', columns: ['distinct_id']), [
        {'distinct_id': 'user_123'},
      ]);
      final columns = await db.rawQuery('PRAGMA table_info(events)');
      expect(columns.map((c) => c['name']), isNot(contains('identity')));
      await db.close();
    });
  });

  group('PayloadSerializer identity', () {
    final session = Session(
      id: 'session1',
      startTime: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      status: SessionStatus.active,
    );

    test('query params carry the identity beside distinct_id', () {
      // WHEN
      final params = PayloadSerializer(
        'token',
      ).buildQueryParams(session, 'user_123', 0, identity: acme);

      // THEN
      expect(params['distinct_id'], 'user_123');
      expect(params['\$user_id'], 'user_123');
      expect(params['\$company_id'], 'acme');
      expect(params['\$device_id'], 'device_1');
    });

    test('query params without an identity are unchanged', () {
      // WHEN
      final params = PayloadSerializer(
        'token',
      ).buildQueryParams(session, 'user_123', 0);

      // THEN
      expect(params.keys, isNot(contains('\$user_id')));
      expect(params.keys, isNot(contains('\$company_id')));
      expect(params.keys, isNot(contains('\$device_id')));
    });
  });
}

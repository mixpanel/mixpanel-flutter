import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/upload/payload_serializer.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session_event.dart';
import 'package:mixpanel_flutter_session_replay/src/models/rrweb_types.dart';

void main() {
  group('PayloadSerializer', () {
    final testToken = 'test-token-abc';
    late PayloadSerializer serializer;

    setUp(() {
      serializer = PayloadSerializer(testToken);
    });

    group('serialize', () {
      test('returns gzip-compressed payload for empty event list', () async {
        // GIVEN
        final events = <SessionReplayEvent>[];
        final session = Session(
          id: 'session-1',
          startTime: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
          status: SessionStatus.active,
        );

        // WHEN
        final result = await serializer.serialize(events, session, 'user-1', 0);

        // THEN
        expect(result.isCompressed, true);

        // Decompress and verify it's an empty JSON array
        final decompressed = gzip.decode(result.body as List<int>);
        final json = utf8.decode(decompressed);
        expect(json, '[]');
      });

      test('sets correct headers', () async {
        // GIVEN
        final expectedContentType = 'application/octet-stream';
        final events = <SessionReplayEvent>[];
        final session = Session(
          id: 'session-1',
          startTime: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
          status: SessionStatus.active,
        );

        // WHEN
        final result = await serializer.serialize(events, session, 'user-1', 0);

        // THEN
        expect(result.headers['Content-Type'], expectedContentType);
        final expectedAuth =
            'Basic ${base64Encode(utf8.encode('$testToken:'))}';
        expect(result.headers['Authorization'], expectedAuth);
      });

      test(
        'converts interaction event to rrweb incremental snapshot format',
        () async {
          // GIVEN
          final expectedRrwebType = RRWebEventType.incrementalSnapshot;
          final expectedSource = RRWebIncrementalSource.mouseInteraction;
          final expectedInteractionType = 7; // touchStart
          final expectedX = 150;
          final expectedY = 300;
          final expectedTimestampMs = 5000;

          final event = SessionReplayEvent(
            sessionId: 'session-1',
            distinctId: 'user-1',
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              expectedTimestampMs,
              isUtc: true,
            ),
            type: EventType.interaction,
            payload: InteractionPayload(
              interactionType: expectedInteractionType,
              x: expectedX.toDouble(),
              y: expectedY.toDouble(),
            ),
          );

          final session = Session(
            id: 'session-1',
            startTime: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
            status: SessionStatus.active,
          );

          // WHEN
          final result = await serializer.serialize(
            [event],
            session,
            'user-1',
            0,
          );

          // THEN
          final decompressed = gzip.decode(result.body as List<int>);
          final json = jsonDecode(utf8.decode(decompressed)) as List<dynamic>;

          expect(json.length, 1);

          final rrwebEvent = json[0] as Map<String, dynamic>;
          expect(rrwebEvent['type'], expectedRrwebType);
          expect(rrwebEvent['timestamp'], expectedTimestampMs);

          final data = rrwebEvent['data'] as Map<String, dynamic>;
          expect(data['source'], expectedSource);
          expect(data['type'], expectedInteractionType);
          expect(data['x'], expectedX);
          expect(data['y'], expectedY);
          expect(data['id'], RRWebNodeIds.mainImage);
        },
      );

      test('converts screenshot event to rrweb full snapshot format', () async {
        // GIVEN
        final expectedRrwebType = RRWebEventType.fullSnapshot;
        final imageData = Uint8List.fromList([0xFF, 0xD8, 0x01, 0x02]);
        final expectedBase64 = base64Encode(imageData);
        final expectedTimestampMs = 5000;

        final event = SessionReplayEvent(
          sessionId: 'session-1',
          distinctId: 'user-1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            expectedTimestampMs,
            isUtc: true,
          ),
          type: EventType.screenshot,
          payload: ScreenshotPayload(imageData: imageData),
        );

        final session = Session(
          id: 'session-1',
          startTime: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
          status: SessionStatus.active,
        );

        // WHEN
        final result = await serializer.serialize(
          [event],
          session,
          'user-1',
          0,
        );

        // THEN
        final decompressed = gzip.decode(result.body as List<int>);
        final json = jsonDecode(utf8.decode(decompressed)) as List<dynamic>;

        expect(json.length, 1);

        final rrwebEvent = json[0] as Map<String, dynamic>;
        expect(rrwebEvent['type'], expectedRrwebType);
        expect(rrwebEvent['timestamp'], expectedTimestampMs);

        // Verify the image is embedded as base64 data URI in the DOM node tree
        final node = rrwebEvent['data']['node'] as Map<String, dynamic>;
        final jsonString = jsonEncode(node);
        expect(jsonString, contains(expectedBase64));
        expect(jsonString, contains('data:image/jpeg;base64,'));
      });

      test('converts metadata event to rrweb meta format', () async {
        // GIVEN
        final expectedRrwebType = RRWebEventType.meta;
        final expectedWidth = 375;
        final expectedHeight = 812;
        final expectedTimestampMs = 5000;

        final event = SessionReplayEvent(
          sessionId: 'session-1',
          distinctId: 'user-1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            expectedTimestampMs,
            isUtc: true,
          ),
          type: EventType.metadata,
          payload: MetadataPayload(
            width: expectedWidth,
            height: expectedHeight,
          ),
        );

        final session = Session(
          id: 'session-1',
          startTime: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
          status: SessionStatus.active,
        );

        // WHEN
        final result = await serializer.serialize(
          [event],
          session,
          'user-1',
          0,
        );

        // THEN
        final decompressed = gzip.decode(result.body as List<int>);
        final json = jsonDecode(utf8.decode(decompressed)) as List<dynamic>;

        expect(json.length, 1);

        final rrwebEvent = json[0] as Map<String, dynamic>;
        expect(rrwebEvent['type'], expectedRrwebType);
        expect(rrwebEvent['timestamp'], expectedTimestampMs);

        final data = rrwebEvent['data'] as Map<String, dynamic>;
        expect(data['width'], expectedWidth);
        expect(data['height'], expectedHeight);
        expect(data['discriminator'], 'dimension');
      });

      test('serializes multiple events in order', () async {
        // GIVEN
        final events = [
          SessionReplayEvent(
            sessionId: 'session-1',
            distinctId: 'user-1',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
            type: EventType.metadata,
            payload: MetadataPayload(width: 375, height: 812),
          ),
          SessionReplayEvent(
            sessionId: 'session-1',
            distinctId: 'user-1',
            timestamp: DateTime.fromMillisecondsSinceEpoch(200, isUtc: true),
            type: EventType.screenshot,
            payload: ScreenshotPayload(imageData: Uint8List.fromList([1, 2])),
          ),
          SessionReplayEvent(
            sessionId: 'session-1',
            distinctId: 'user-1',
            timestamp: DateTime.fromMillisecondsSinceEpoch(300, isUtc: true),
            type: EventType.interaction,
            payload: InteractionPayload(interactionType: 7, x: 10.0, y: 20.0),
          ),
        ];

        final session = Session(
          id: 'session-1',
          startTime: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
          status: SessionStatus.active,
        );

        // WHEN
        final result = await serializer.serialize(events, session, 'user-1', 0);

        // THEN
        final decompressed = gzip.decode(result.body as List<int>);
        final json = jsonDecode(utf8.decode(decompressed)) as List<dynamic>;

        expect(json.length, 3);
        expect(json[0]['type'], RRWebEventType.meta);
        expect(json[1]['type'], RRWebEventType.fullSnapshot);
        expect(json[2]['type'], RRWebEventType.incrementalSnapshot);
      });
    });

    group('buildAuthHeader', () {
      test('creates correct Basic auth header', () {
        // GIVEN
        final expectedCredentials = base64Encode(utf8.encode('$testToken:'));
        final expectedHeader = 'Basic $expectedCredentials';

        // WHEN
        final result = serializer.buildAuthHeader(testToken);

        // THEN
        expect(result, expectedHeader);
      });
    });

    group('buildQueryParams', () {
      test('includes required static parameters', () {
        // GIVEN
        final expectedDistinctId = 'user-123';
        final expectedSequenceNumber = '5';
        final expectedSessionId = 'session-abc';
        final expectedFormat = 'gzip';
        final session = Session(
          id: expectedSessionId,
          startTime: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
          status: SessionStatus.active,
        );

        // WHEN
        final params = serializer.buildQueryParams(
          session,
          expectedDistinctId,
          5,
        );

        // THEN
        expect(params['format'], expectedFormat);
        expect(params['distinct_id'], expectedDistinctId);
        expect(params['seq'], expectedSequenceNumber);
        expect(params['replay_id'], expectedSessionId);
        expect(params['\$lib_version'], endsWith('-flutter'));
      });

      test('includes dynamic timestamp parameters', () {
        fakeAsync((async) {
          // GIVEN
          final sessionStartTime = DateTime.fromMillisecondsSinceEpoch(
            1000,
            isUtc: true,
          );
          final session = Session(
            id: 'session-1',
            startTime: sessionStartTime,
            status: SessionStatus.active,
          );

          final expectedBatchStartTime =
              clock.now().millisecondsSinceEpoch / 1000.0;
          final expectedReplayLengthMs = clock
              .now()
              .difference(sessionStartTime)
              .inMilliseconds;

          // WHEN
          final params = serializer.buildQueryParams(session, 'user-1', 0);

          // THEN
          final batchStartTime = double.parse(params['batch_start_time']!);
          expect(batchStartTime, expectedBatchStartTime);

          final replayStartTime = double.parse(params['replay_start_time']!);
          expect(replayStartTime, 1.0); // 1000ms = 1.0s

          final replayLengthMs = int.parse(params['replay_length_ms']!);
          expect(replayLengthMs, expectedReplayLengthMs);
        });
      });
    });
  });
}

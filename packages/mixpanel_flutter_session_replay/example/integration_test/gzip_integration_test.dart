import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/upload/payload_serializer.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/upload/rrweb_event.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session_event.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session.dart';
import 'package:mixpanel_flutter_session_replay/src/models/rrweb_types.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final testToken = 'test-token-abc123';
  final testSession = Session(
    id: 'session-001',
    startTime: DateTime.fromMillisecondsSinceEpoch(1000000, isUtc: true),
    status: SessionStatus.active,
  );

  /// Decompress gzipped bytes and decode the JSON payload.
  List<dynamic> decompressPayload(List<int> compressed) {
    final decompressed = gzip.decode(compressed);
    final jsonString = utf8.decode(decompressed);
    return jsonDecode(jsonString) as List<dynamic>;
  }

  testWidgets(
    'mixed event batch roundtrips through gzip with correct structure',
    (tester) async {
      await tester.runAsync(() async {
        final serializer = PayloadSerializer(testToken);

        final jpegData = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

        final events = [
          SessionReplayEvent(
            sessionId: 'session-001',
            distinctId: 'user1',
            timestamp: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
            type: EventType.metadata,
            payload: MetadataPayload(width: 720, height: 1280),
          ),
          SessionReplayEvent(
            sessionId: 'session-001',
            distinctId: 'user1',
            timestamp: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
            type: EventType.screenshot,
            payload: ScreenshotPayload(imageData: jpegData),
          ),
          SessionReplayEvent(
            sessionId: 'session-001',
            distinctId: 'user1',
            timestamp: DateTime.fromMillisecondsSinceEpoch(3000, isUtc: true),
            type: EventType.interaction,
            payload: InteractionPayload(
              interactionType: RRWebMouseInteraction.touchStart,
              x: 100,
              y: 200,
            ),
          ),
        ];

        final result = await serializer.serialize(
          events,
          testSession,
          'user1',
          0,
        );

        // Verify gzip headers
        expect(result.isCompressed, isTrue);
        expect(result.headers['Content-Type'], 'application/octet-stream');

        final bytes = result.body as List<int>;
        // Gzip magic number: 0x1F 0x8B
        expect(bytes[0], 0x1F);
        expect(bytes[1], 0x8B);

        // Decompress and verify all events survived
        final decoded = decompressPayload(bytes);
        expect(decoded.length, 3);

        // Meta event
        expect(decoded[0]['type'], RRWebEventType.meta);
        expect(decoded[0]['timestamp'], 1000);
        expect(decoded[0]['data']['width'], 720);
        expect(decoded[0]['data']['height'], 1280);

        // Screenshot event — walk the DOM to recover the image bytes
        expect(decoded[1]['type'], RRWebEventType.fullSnapshot);
        expect(decoded[1]['timestamp'], 2000);
        final node = decoded[1]['data']['node'] as Map<String, dynamic>;
        final html = (node['childNodes'] as List)[1] as Map<String, dynamic>;
        final body = (html['childNodes'] as List)[1] as Map<String, dynamic>;
        final screen = (body['childNodes'] as List)[0] as Map<String, dynamic>;
        final img = (screen['childNodes'] as List)[0] as Map<String, dynamic>;
        final src = img['attributes']['src'] as String;
        expect(src, startsWith('data:image/jpeg;base64,'));
        final recoveredBytes = base64Decode(src.split(',')[1]);
        expect(recoveredBytes, jpegData);

        // Interaction event
        expect(decoded[2]['type'], RRWebEventType.incrementalSnapshot);
        expect(decoded[2]['timestamp'], 3000);
        expect(decoded[2]['data']['x'], 100);
        expect(decoded[2]['data']['y'], 200);
      });
    },
  );

  testWidgets('large batch compresses and decompresses without data loss', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final serializer = PayloadSerializer(testToken);

      // 100 screenshot events, each with 10KB of image data (~1MB+ uncompressed JSON)
      final events = List.generate(
        100,
        (i) => SessionReplayEvent(
          sessionId: 'session-001',
          distinctId: 'user1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            1000 + (i * 100),
            isUtc: true,
          ),
          type: EventType.screenshot,
          payload: ScreenshotPayload(
            imageData: Uint8List.fromList([
              0xFF,
              0xD8,
              0xFF,
              0xE0,
              ...List.generate(10240, (j) => (i + j) % 256),
            ]),
          ),
        ),
      );

      final result = await serializer.serialize(
        events,
        testSession,
        'user1',
        0,
      );
      final compressed = result.body as List<int>;
      final decoded = decompressPayload(compressed);

      expect(decoded.length, 100);

      // Verify compression actually reduced size
      final uncompressedJson = jsonEncode(
        events
            .map((e) => RRWebEvent.fromSessionReplayEvent(e).toJson())
            .toList(),
      );
      expect(compressed.length, lessThan(utf8.encode(uncompressedJson).length));

      // Verify first and last events survived
      expect(decoded.first['timestamp'], 1000);
      expect(decoded.last['timestamp'], 1000 + (99 * 100));
    });
  });

  testWidgets('compressed output has valid gzip magic bytes', (tester) async {
    await tester.runAsync(() async {
      final serializer = PayloadSerializer(testToken);

      final result = await serializer.serialize(
        [
          SessionReplayEvent(
            sessionId: 'session-001',
            distinctId: 'user1',
            timestamp: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
            type: EventType.metadata,
            payload: MetadataPayload(width: 100, height: 200),
          ),
        ],
        testSession,
        'user1',
        0,
      );
      final bytes = result.body as List<int>;

      // Gzip magic number
      expect(bytes[0], 0x1F);
      expect(bytes[1], 0x8B);

      // Decompression should produce valid UTF-8 JSON
      final decompressed = gzip.decode(bytes);
      final parsed = jsonDecode(utf8.decode(decompressed));
      expect(parsed, isList);
      expect((parsed as List).length, 1);
    });
  });
}

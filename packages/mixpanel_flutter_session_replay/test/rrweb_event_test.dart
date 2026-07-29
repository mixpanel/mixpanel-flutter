import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/upload/rrweb_event.dart';
import 'package:mixpanel_flutter_session_replay/src/models/rrweb_types.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session_event.dart';
import 'package:mixpanel_flutter_session_replay/src/models/wireframe.dart';
import 'package:mixpanel_flutter_session_replay/src/models/wireframes_options.dart'
    show MaskDecision;

void main() {
  group('RRWebEvent', () {
    group('fromSessionReplayEvent', () {
      test('converts metadata event to rrweb meta format', () {
        // GIVEN
        final expectedTimestampMs = 5000;
        final expectedWidth = 375;
        final expectedHeight = 812;
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

        // WHEN
        final rrweb = RRWebEvent.fromSessionReplayEvent(event);

        // THEN
        expect(rrweb.type, RRWebEventType.meta);
        expect(rrweb.timestamp, expectedTimestampMs);
        expect(rrweb.data['discriminator'], 'dimension');
        expect(rrweb.data['width'], expectedWidth);
        expect(rrweb.data['height'], expectedHeight);
      });

      test('converts interaction event to rrweb incremental snapshot', () {
        // GIVEN
        final expectedTimestampMs = 3000;
        final expectedInteractionType = RRWebMouseInteraction.touchStart;
        final expectedX = 150;
        final expectedY = 300;
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

        // WHEN
        final rrweb = RRWebEvent.fromSessionReplayEvent(event);

        // THEN
        expect(rrweb.type, RRWebEventType.incrementalSnapshot);
        expect(rrweb.timestamp, expectedTimestampMs);
        expect(rrweb.data['source'], RRWebIncrementalSource.mouseInteraction);
        expect(rrweb.data['type'], expectedInteractionType);
        expect(rrweb.data['id'], RRWebNodeIds.mainImage);
        expect(rrweb.data['x'], expectedX);
        expect(rrweb.data['y'], expectedY);
      });

      test('converts JPEG screenshot event to rrweb full snapshot', () {
        // GIVEN
        final expectedTimestampMs = 2000;
        final imageData = Uint8List.fromList([0xFF, 0xD8, 0x01, 0x02]);
        final expectedBase64 = base64Encode(imageData);
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

        // WHEN
        final rrweb = RRWebEvent.fromSessionReplayEvent(event);

        // THEN
        expect(rrweb.type, RRWebEventType.fullSnapshot);
        expect(rrweb.timestamp, expectedTimestampMs);
        expect(rrweb.data['discriminator'], 'node');

        final node = rrweb.data['node'] as Map<String, dynamic>;
        expect(node['type'], RRWebNodeType.document);
        expect(node['id'], RRWebNodeIds.document);

        // Verify image src contains JPEG mime type and base64 data
        final imgNode = _findNodeById(node, RRWebNodeIds.mainImage);
        expect(imgNode, isNotNull);
        expect(imgNode!['tagName'], 'img');
        expect(
          imgNode['attributes']['src'],
          'data:image/jpeg;base64,$expectedBase64',
        );
      });

      test('converts PNG screenshot event with correct mime type', () {
        // GIVEN - PNG magic bytes: 89 50 4E 47
        final pngData = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D]);
        final expectedBase64 = base64Encode(pngData);
        final event = SessionReplayEvent(
          sessionId: 'session-1',
          distinctId: 'user-1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
          type: EventType.screenshot,
          payload: ScreenshotPayload(imageData: pngData),
        );

        // WHEN
        final rrweb = RRWebEvent.fromSessionReplayEvent(event);

        // THEN
        final node = rrweb.data['node'] as Map<String, dynamic>;
        final imgNode = _findNodeById(node, RRWebNodeIds.mainImage);
        expect(
          imgNode!['attributes']['src'],
          'data:image/png;base64,$expectedBase64',
        );
      });

      test('converts wireframe event to rrweb Custom event', () {
        // GIVEN — Notion spec sample payload
        final timestampMs = 1_749_317_600_000;
        final event = SessionReplayEvent(
          sessionId: 'session-1',
          distinctId: 'user-1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            timestampMs,
            isUtc: true,
          ),
          type: EventType.wireframe,
          payload: WireframePayload(
            viewportWidth: 1080,
            viewportHeight: 1920,
            elements: [
              WireframeElement(
                role: WireframeRole.text,
                text: 'Welcome',
                bounds: const Rect.fromLTWH(24, 120, 400, 40),
                maskDecision: MaskDecision.none,
              ),
              WireframeElement(
                role: WireframeRole.input,
                text: null,
                bounds: const Rect.fromLTWH(40, 600, 400, 48),
                maskDecision: MaskDecision.textEntry,
              ),
              WireframeElement(
                role: WireframeRole.button,
                text: 'Continue',
                bounds: const Rect.fromLTWH(40, 800, 300, 56),
                maskDecision: MaskDecision.none,
              ),
              WireframeElement(
                role: WireframeRole.image,
                text: 'avatar',
                bounds: const Rect.fromLTWH(24, 40, 64, 64),
                maskDecision: MaskDecision.none,
              ),
            ],
          ),
        );

        // WHEN
        final rrweb = RRWebEvent.fromSessionReplayEvent(event);

        // THEN — Custom event with wireframe tag
        expect(rrweb.type, RRWebEventType.custom);
        expect(rrweb.timestamp, timestampMs);
        expect(rrweb.data['tag'], RRWebCustomTags.wireframe);
        final payload = rrweb.data['payload'] as Map<String, dynamic>;
        expect(payload['viewport'], [1080, 1920]);
        final elements = payload['elements'] as List;
        expect(elements, hasLength(4));
        expect(elements[0], {
          'role': 'text',
          'text': 'Welcome',
          'bounds': [24, 120, 400, 40],
        });
        expect(elements[1], {
          'role': 'input',
          'text': null,
          'bounds': [40, 600, 400, 48],
        });
        expect(elements[2], {
          'role': 'button',
          'text': 'Continue',
          'bounds': [40, 800, 300, 56],
        });
        expect(elements[3], {
          'role': 'image',
          'text': 'avatar',
          'bounds': [24, 40, 64, 64],
        });
      });

      test('wireframe event preserves null text as JSON null', () {
        // GIVEN — element with masked (null) text
        final event = SessionReplayEvent(
          sessionId: 'session-1',
          distinctId: 'user-1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
          type: EventType.wireframe,
          payload: WireframePayload(
            viewportWidth: 100,
            viewportHeight: 100,
            elements: [
              WireframeElement(
                role: WireframeRole.text,
                text: null,
                bounds: const Rect.fromLTWH(0, 0, 10, 10),
                maskDecision: MaskDecision.geometric,
              ),
            ],
          ),
        );

        // WHEN — round-trip through JSON to verify null survives
        final rrweb = RRWebEvent.fromSessionReplayEvent(event);
        final encoded = jsonEncode(rrweb.toJson());
        final decoded = jsonDecode(encoded) as Map<String, dynamic>;

        // THEN
        final payload = decoded['data']['payload'] as Map<String, dynamic>;
        final elements = payload['elements'] as List;
        expect(elements.single['text'], isNull);
      });

      test('screenshot DOM structure has expected node IDs', () {
        // GIVEN
        final event = SessionReplayEvent(
          sessionId: 'session-1',
          distinctId: 'user-1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
          type: EventType.screenshot,
          payload: ScreenshotPayload(
            imageData: Uint8List.fromList([0xFF, 0xD8]),
          ),
        );

        // WHEN
        final rrweb = RRWebEvent.fromSessionReplayEvent(event);

        // THEN - verify the DOM tree node IDs
        final root = rrweb.data['node'] as Map<String, dynamic>;
        expect(_findNodeById(root, RRWebNodeIds.document), isNotNull);
        expect(_findNodeById(root, RRWebNodeIds.documentType), isNotNull);
        expect(_findNodeById(root, RRWebNodeIds.html), isNotNull);
        expect(_findNodeById(root, RRWebNodeIds.head), isNotNull);
        expect(_findNodeById(root, RRWebNodeIds.style), isNotNull);
        expect(_findNodeById(root, RRWebNodeIds.styleText), isNotNull);
        expect(_findNodeById(root, RRWebNodeIds.body), isNotNull);
        expect(_findNodeById(root, RRWebNodeIds.imageContainer), isNotNull);
        expect(_findNodeById(root, RRWebNodeIds.mainImage), isNotNull);
      });
    });

    group('toJson', () {
      test('serializes all fields', () {
        // GIVEN
        final rrweb = RRWebEvent(
          type: RRWebEventType.meta,
          timestamp: 1000,
          data: {'width': 375, 'height': 812},
        );

        // WHEN
        final json = rrweb.toJson();

        // THEN
        expect(json['type'], RRWebEventType.meta);
        expect(json['timestamp'], 1000);
        expect(json['data'], {'width': 375, 'height': 812});
      });
    });
  });
}

/// Recursively find a node by its 'id' field in the DOM tree
Map<String, dynamic>? _findNodeById(Map<String, dynamic> node, int id) {
  if (node['id'] == id) return node;
  final children = node['childNodes'] as List<dynamic>?;
  if (children == null) return null;
  for (final child in children) {
    final result = _findNodeById(child as Map<String, dynamic>, id);
    if (result != null) return result;
  }
  return null;
}

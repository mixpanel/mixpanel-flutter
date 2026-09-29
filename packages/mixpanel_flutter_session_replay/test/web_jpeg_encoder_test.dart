@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/platform/web_jpeg_encoder.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:web/web.dart' as web;

/// A [size]x[size] snapshot of a solid red canvas.
Future<web.ImageBitmap> _redBitmap(int size) {
  final canvas = web.HTMLCanvasElement()
    ..width = size
    ..height = size;
  final context = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
  context.fillStyle = '#ff0000'.toJS;
  context.fillRect(0, 0, size, size);
  return web.window.createImageBitmap(canvas).toDart;
}

void main() {
  test('Web Worker initializes and encodes a bitmap as JPEG', () async {
    final encoder = WebJpegEncoder(logger: MixpanelLogger(LogLevel.none));
    addTearDown(encoder.dispose);

    await encoder.initialize();
    final result = await encoder.encode(
      imageBitmap: await _redBitmap(2),
      width: 2,
      height: 2,
      maskRects: const [],
    );

    expect(result, isNotNull);
    expect(result!.take(2), <int>[0xff, 0xd8]);
    expect(result.skip(result.length - 2), <int>[0xff, 0xd9]);
  });

  test('Web Worker paints privacy masks before JPEG encoding', () async {
    final encoder = WebJpegEncoder(
      logger: MixpanelLogger(LogLevel.none),
      jpegQuality: 1,
    );
    addTearDown(encoder.dispose);
    await encoder.initialize();

    final result = await encoder.encode(
      imageBitmap: await _redBitmap(32),
      width: 32,
      height: 32,
      maskRects: const [Rect.fromLTWH(0, 0, 32, 32)],
    );

    final pixel = img.decodeJpg(result!)!.getPixel(16, 16);
    expect(pixel.r, closeTo(204, 8));
    expect(pixel.g, closeTo(204, 8));
    expect(pixel.b, closeTo(204, 8));
  });
}

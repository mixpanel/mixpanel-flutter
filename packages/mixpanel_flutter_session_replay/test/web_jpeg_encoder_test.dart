@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/platform/web_jpeg_encoder.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/platform/web_image_worker.dart';
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
  for (final eventType in ['error', 'messageerror']) {
    test('worker $eventType rejects pending encoding immediately', () async {
      // GIVEN a worker whose browser message delivery fails
      final prototype =
          (globalContext['Worker'] as JSObject)['prototype'] as JSObject;
      final originalPostMessage = prototype['postMessage'];
      addTearDown(() => prototype['postMessage'] = originalPostMessage);
      final web.Event event = eventType == 'messageerror'
          ? web.MessageEvent(eventType, web.MessageEventInit(cancelable: true))
          : web.Event(eventType, web.EventInit(cancelable: true));
      prototype['postMessage'] =
          ((web.Worker worker, JSAny? message, JSAny? transfer) {
            scheduleMicrotask(() => worker.dispatchEvent(event));
          }).toJSCaptureThis;
      final worker = WebImageWorker.create()!;
      addTearDown(worker.dispose);
      final bitmap = await _redBitmap(2);
      addTearDown(() => bitmap.close());

      // WHEN the browser reports the error during encoding
      final pending = worker.processImageBitmap(
        imageBitmap: bitmap,
        width: 2,
        height: 2,
        jpegQuality: 1,
        maskRects: const [],
      );

      // THEN it fails without waiting for the encoder's five-second timeout
      await expectLater(
        pending.timeout(const Duration(seconds: 1)),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Worker $eventType'),
          ),
        ),
      );
      expect(event.defaultPrevented, isTrue);
    });
  }

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

  test('should stop recreating the worker after repeated failures', () async {
    // GIVEN an initialized encoder
    final encoder = WebJpegEncoder(logger: MixpanelLogger(LogLevel.none));
    addTearDown(encoder.dispose);
    await encoder.initialize();

    // WHEN encoding keeps failing the same way (a bitmap that can no longer
    // be transferred to the worker)
    for (var i = 0; i < WebJpegEncoder.maxConsecutiveFailures; i++) {
      final bitmap = await _redBitmap(2);
      bitmap.close();
      final result = await encoder.encode(
        imageBitmap: bitmap,
        width: 2,
        height: 2,
        maskRects: const [],
      );
      expect(result, isNull);
    }

    // THEN capture is disabled instead of rebuilding the worker every frame
    expect(encoder.isAvailable, isFalse);
  });

  test('should keep the worker after a failure followed by success', () async {
    // GIVEN one failed encode
    final encoder = WebJpegEncoder(logger: MixpanelLogger(LogLevel.none));
    addTearDown(encoder.dispose);
    await encoder.initialize();
    final closed = await _redBitmap(2);
    closed.close();
    await encoder.encode(
      imageBitmap: closed,
      width: 2,
      height: 2,
      maskRects: const [],
    );

    // WHEN encoding then succeeds, and fails again below the limit
    final ok = await encoder.encode(
      imageBitmap: await _redBitmap(2),
      width: 2,
      height: 2,
      maskRects: const [],
    );
    for (var i = 0; i < WebJpegEncoder.maxConsecutiveFailures - 1; i++) {
      final bitmap = await _redBitmap(2);
      bitmap.close();
      await encoder.encode(
        imageBitmap: bitmap,
        width: 2,
        height: 2,
        maskRects: const [],
      );
    }

    // THEN the success reset the count, so the encoder is still available
    expect(ok, isNotNull);
    expect(encoder.isAvailable, isTrue);
  });
}

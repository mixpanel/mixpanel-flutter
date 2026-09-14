@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:ui' show Rect, Size;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/platform/web_image_compressor.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:web/web.dart' as web;

void main() {
  final rgba = Uint8List.fromList(<int>[
    255,
    0,
    0,
    255,
    0,
    255,
    0,
    255,
    0,
    0,
    255,
    255,
    255,
    255,
    255,
    255,
  ]);

  test('Web Worker initializes and encodes RGBA as JPEG', () async {
    final compressor = WebImageCompressor(
      logger: MixpanelLogger(LogLevel.none),
    );
    addTearDown(compressor.dispose);

    await compressor.initialize();
    final result = await compressor.compress(
      Uint8List.fromList(rgba),
      width: 2,
      height: 2,
    );

    expect(result, isNotNull);
    expect(result!.take(2), <int>[0xff, 0xd8]);
    expect(result.skip(result.length - 2), <int>[0xff, 0xd9]);
  });

  test('Web Worker paints privacy masks before JPEG encoding', () async {
    final compressor = WebImageCompressor(
      logger: MixpanelLogger(LogLevel.none),
      jpegQuality: 1,
    );
    addTearDown(compressor.dispose);
    await compressor.initialize();
    final red = Uint8List.fromList(
      List<int>.generate(
        32 * 32 * 4,
        (index) => switch (index % 4) {
          0 => 255,
          3 => 255,
          _ => 0,
        },
      ),
    );

    final result = await compressor.compress(
      red,
      width: 32,
      height: 32,
      maskRects: const [Rect.fromLTWH(0, 0, 32, 32)],
    );

    final pixel = img.decodeJpg(result!)!.getPixel(16, 16);
    expect(pixel.r, closeTo(204, 8));
    expect(pixel.g, closeTo(204, 8));
    expect(pixel.b, closeTo(204, 8));
  });

  test(
    'rendered surface capture scales a DPR canvas and encodes real pixels',
    () async {
      // Given a 2x backing canvas with a unique logical size.
      final canvas = _appendCanvas(
        logicalWidth: 37,
        logicalHeight: 29,
        backingWidth: 74,
        backingHeight: 58,
      );
      addTearDown(() => _removeCanvasHost(canvas));
      final context = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
      context.fillStyle = '#ff0000'.toJS;
      context.fillRect(0, 0, canvas.width, canvas.height);
      final compressor = WebImageCompressor(
        logger: MixpanelLogger(LogLevel.none),
        jpegQuality: 1,
      );
      addTearDown(compressor.dispose);
      await compressor.initialize();

      // When the browser surface is resized entirely inside the worker.
      final result = await compressor.captureRenderedSurface(
        logicalSize: const Size(37, 29),
        outputWidth: 19,
        outputHeight: 15,
      );

      // Then the encoded image has the requested size and source color.
      final image = img.decodeJpg(result!)!;
      expect(image.width, 19);
      expect(image.height, 15);
      final pixel = image.getPixel(9, 7);
      expect(pixel.r, greaterThan(240));
      expect(pixel.g, lessThan(15));
      expect(pixel.b, lessThan(15));
    },
  );

  test('rendered surface masks are painted in output coordinates', () async {
    // Given a red browser canvas discovered through an open shadow root.
    final host = web.document.createElement('flt-renderer');
    web.document.body!.appendChild(host);
    addTearDown(() => host.remove());
    final shadow = host.attachShadow(web.ShadowRootInit(mode: 'open'));
    final canvas = _createCanvas(
      logicalWidth: 43,
      logicalHeight: 31,
      backingWidth: 86,
      backingHeight: 62,
    );
    shadow.appendChild(canvas);
    final context = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
    context.fillStyle = '#ff0000'.toJS;
    context.fillRect(0, 0, canvas.width, canvas.height);
    final compressor = WebImageCompressor(
      logger: MixpanelLogger(LogLevel.none),
      jpegQuality: 1,
    );
    addTearDown(compressor.dispose);
    await compressor.initialize();

    // When a partial privacy mask is supplied in output coordinates.
    final result = await compressor.captureRenderedSurface(
      logicalSize: const Size(43, 31),
      outputWidth: 22,
      outputHeight: 16,
      maskRects: const [Rect.fromLTWH(5, 4, 10, 8)],
    );

    // Then the worker masks exactly that region before encoding it.
    final image = img.decodeJpg(result!)!;
    final maskedPixel = image.getPixel(10, 8);
    expect(maskedPixel.r, closeTo(204, 8));
    expect(maskedPixel.g, closeTo(204, 8));
    expect(maskedPixel.b, closeTo(204, 8));
    final unmaskedPixel = image.getPixel(2, 2);
    expect(unmaskedPixel.r, greaterThan(240));
    expect(unmaskedPixel.g, lessThan(15));
    expect(unmaskedPixel.b, lessThan(15));
  });

  test(
    'rendered surface capture fails closed when selection is ambiguous',
    () async {
      // Given two visible canvases with the same logical dimensions.
      final first = _appendCanvas(
        logicalWidth: 47,
        logicalHeight: 33,
        backingWidth: 47,
        backingHeight: 33,
      );
      final second = _appendCanvas(
        logicalWidth: 47,
        logicalHeight: 33,
        backingWidth: 94,
        backingHeight: 66,
      );
      addTearDown(() => _removeCanvasHost(first));
      addTearDown(() => _removeCanvasHost(second));
      final compressor = WebImageCompressor(
        logger: MixpanelLogger(LogLevel.none),
      );
      addTearDown(compressor.dispose);
      await compressor.initialize();

      // When capture cannot identify a unique source surface.
      final result = await compressor.captureRenderedSurface(
        logicalSize: const Size(47, 33),
        outputWidth: 47,
        outputHeight: 33,
      );

      // Then no possibly incorrect or unmasked image is returned.
      expect(result, isNull);
      expect(compressor.isAvailable, isTrue);
    },
  );

  test('ignores an unrelated viewport-sized light DOM canvas', () async {
    final unrelated = _createCanvas(
      logicalWidth: 49,
      logicalHeight: 35,
      backingWidth: 49,
      backingHeight: 35,
    );
    web.document.body!.appendChild(unrelated);
    addTearDown(() => unrelated.remove());
    final unrelatedContext =
        unrelated.getContext('2d')! as web.CanvasRenderingContext2D;
    unrelatedContext.fillStyle = '#ff0000'.toJS;
    unrelatedContext.fillRect(0, 0, unrelated.width, unrelated.height);

    final flutterCanvas = _appendCanvas(
      logicalWidth: 49,
      logicalHeight: 35,
      backingWidth: 49,
      backingHeight: 35,
    );
    addTearDown(() => _removeCanvasHost(flutterCanvas));
    final flutterContext =
        flutterCanvas.getContext('2d')! as web.CanvasRenderingContext2D;
    flutterContext.fillStyle = '#00ff00'.toJS;
    flutterContext.fillRect(0, 0, flutterCanvas.width, flutterCanvas.height);

    final compressor = WebImageCompressor(
      logger: MixpanelLogger(LogLevel.none),
      jpegQuality: 1,
    );
    addTearDown(compressor.dispose);
    await compressor.initialize();

    final result = await compressor.captureRenderedSurface(
      logicalSize: const Size(49, 35),
      outputWidth: 49,
      outputHeight: 35,
    );

    final pixel = img.decodeJpg(result!)!.getPixel(24, 17);
    expect(pixel.r, lessThan(15));
    expect(pixel.g, greaterThan(240));
    expect(pixel.b, lessThan(15));
  });

  test('fails closed when only an unrelated canvas matches', () async {
    final unrelated = _createCanvas(
      logicalWidth: 51,
      logicalHeight: 37,
      backingWidth: 51,
      backingHeight: 37,
    );
    web.document.body!.appendChild(unrelated);
    addTearDown(() => unrelated.remove());
    final compressor = WebImageCompressor(
      logger: MixpanelLogger(LogLevel.none),
    );
    addTearDown(compressor.dispose);
    await compressor.initialize();

    final result = await compressor.captureRenderedSurface(
      logicalSize: const Size(51, 37),
      outputWidth: 51,
      outputHeight: 37,
    );

    expect(result, isNull);
  });

  test(
    'rendered surface capture follows canvas resize and orientation',
    () async {
      final canvas = _appendCanvas(
        logicalWidth: 53,
        logicalHeight: 39,
        backingWidth: 106,
        backingHeight: 78,
      );
      addTearDown(() => _removeCanvasHost(canvas));
      final compressor = WebImageCompressor(
        logger: MixpanelLogger(LogLevel.none),
      );
      addTearDown(compressor.dispose);
      await compressor.initialize();

      final portrait = await compressor.captureRenderedSurface(
        logicalSize: const Size(53, 39),
        outputWidth: 27,
        outputHeight: 20,
      );
      canvas
        ..width = 78
        ..height = 106
        ..style.width = '39px'
        ..style.height = '53px';
      final landscape = await compressor.captureRenderedSurface(
        logicalSize: const Size(39, 53),
        outputWidth: 20,
        outputHeight: 27,
      );

      final portraitImage = img.decodeJpg(portrait!)!;
      final landscapeImage = img.decodeJpg(landscape!)!;
      expect((portraitImage.width, portraitImage.height), const (27, 20));
      expect((landscapeImage.width, landscapeImage.height), const (20, 27));
    },
  );

  test(
    'rendered surface capture fails closed when no canvas matches',
    () async {
      final compressor = WebImageCompressor(
        logger: MixpanelLogger(LogLevel.none),
      );
      addTearDown(compressor.dispose);
      await compressor.initialize();

      final result = await compressor.captureRenderedSurface(
        logicalSize: const Size(8765, 4321),
        outputWidth: 10,
        outputHeight: 10,
      );

      expect(result, isNull);
      expect(compressor.isAvailable, isTrue);
    },
  );

  test('rendered surface capture rejects multiple Flutter views', () async {
    final firstView = web.document.createElement('flutter-view');
    final secondView = web.document.createElement('flutter-view');
    web.document.body!
      ..appendChild(firstView)
      ..appendChild(secondView);
    addTearDown(() => firstView.remove());
    addTearDown(() => secondView.remove());
    final canvas = _appendCanvas(
      logicalWidth: 59,
      logicalHeight: 41,
      backingWidth: 59,
      backingHeight: 41,
    );
    addTearDown(() => _removeCanvasHost(canvas));
    final compressor = WebImageCompressor(
      logger: MixpanelLogger(LogLevel.none),
    );
    addTearDown(compressor.dispose);
    await compressor.initialize();

    final result = await compressor.captureRenderedSurface(
      logicalSize: const Size(59, 41),
      outputWidth: 59,
      outputHeight: 41,
    );

    expect(result, isNull);
  });

  test(
    'rendered surface capture masks the entire frame for platform views',
    () async {
      final platformView = web.document.createElement('flt-platform-view');
      web.document.body!.appendChild(platformView);
      addTearDown(() => platformView.remove());
      final canvas = _appendCanvas(
        logicalWidth: 61,
        logicalHeight: 43,
        backingWidth: 61,
        backingHeight: 43,
      );
      addTearDown(() => _removeCanvasHost(canvas));
      final context = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
      context.fillStyle = '#ff0000'.toJS;
      context.fillRect(0, 0, canvas.width, canvas.height);
      final compressor = WebImageCompressor(
        logger: MixpanelLogger(LogLevel.none),
      );
      addTearDown(compressor.dispose);
      await compressor.initialize();

      final result = await compressor.captureRenderedSurface(
        logicalSize: const Size(61, 43),
        outputWidth: 61,
        outputHeight: 43,
      );

      final pixel = img.decodeJpg(result!)!.getPixel(30, 21);
      expect(pixel.r, closeTo(204, 8));
      expect(pixel.g, closeTo(204, 8));
      expect(pixel.b, closeTo(204, 8));
    },
  );

  test('platform-view masking can be explicitly disabled', () async {
    final platformView = web.document.createElement('flt-platform-view');
    web.document.body!.appendChild(platformView);
    addTearDown(() => platformView.remove());
    final canvas = _appendCanvas(
      logicalWidth: 63,
      logicalHeight: 45,
      backingWidth: 63,
      backingHeight: 45,
    );
    addTearDown(() => _removeCanvasHost(canvas));
    final context = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
    context.fillStyle = '#ff0000'.toJS;
    context.fillRect(0, 0, canvas.width, canvas.height);
    final compressor = WebImageCompressor(
      logger: MixpanelLogger(LogLevel.none),
      jpegQuality: 1,
      platformViewCapturePolicy: WebPlatformViewCapturePolicy.captureNormally,
    );
    addTearDown(compressor.dispose);
    await compressor.initialize();

    final result = await compressor.captureRenderedSurface(
      logicalSize: const Size(63, 45),
      outputWidth: 63,
      outputHeight: 45,
    );

    final pixel = img.decodeJpg(result!)!.getPixel(31, 22);
    expect(pixel.r, greaterThan(240));
    expect(pixel.g, lessThan(15));
    expect(pixel.b, lessThan(15));
  });

  test('ImageBitmap is immutable before snapshot validation runs', () async {
    final canvas = _appendCanvas(
      logicalWidth: 67,
      logicalHeight: 45,
      backingWidth: 134,
      backingHeight: 90,
    );
    addTearDown(() => _removeCanvasHost(canvas));
    final context = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
    context.fillStyle = '#ff0000'.toJS;
    context.fillRect(0, 0, canvas.width, canvas.height);
    final compressor = WebImageCompressor(
      logger: MixpanelLogger(LogLevel.none),
      jpegQuality: 1,
    );
    addTearDown(compressor.dispose);
    await compressor.initialize();

    final result = await compressor.captureRenderedSurface(
      logicalSize: const Size(67, 45),
      outputWidth: 50,
      outputHeight: 34,
      validateSnapshot: () {
        context.fillStyle = '#0000ff'.toJS;
        context.fillRect(0, 0, canvas.width, canvas.height);
        return true;
      },
    );

    final pixel = img.decodeJpg(result!)!.getPixel(25, 17);
    expect(pixel.r, greaterThan(240));
    expect(pixel.g, lessThan(15));
    expect(pixel.b, lessThan(15));
  });

  test('failed post-snapshot validation discards ImageBitmap', () async {
    final canvas = _appendCanvas(
      logicalWidth: 71,
      logicalHeight: 49,
      backingWidth: 71,
      backingHeight: 49,
    );
    addTearDown(() => _removeCanvasHost(canvas));
    final compressor = WebImageCompressor(
      logger: MixpanelLogger(LogLevel.none),
    );
    addTearDown(compressor.dispose);
    await compressor.initialize();
    var validationCalls = 0;

    final result = await compressor.captureRenderedSurface(
      logicalSize: const Size(71, 49),
      outputWidth: 53,
      outputHeight: 37,
      validateSnapshot: () {
        validationCalls++;
        return false;
      },
    );

    expect(result, isNull);
    expect(validationCalls, 1);
    expect(compressor.isAvailable, isTrue);
  });
}

web.HTMLCanvasElement _appendCanvas({
  required int logicalWidth,
  required int logicalHeight,
  required int backingWidth,
  required int backingHeight,
}) {
  final canvas = _createCanvas(
    logicalWidth: logicalWidth,
    logicalHeight: logicalHeight,
    backingWidth: backingWidth,
    backingHeight: backingHeight,
  );
  final host = web.document.createElement('flt-renderer');
  web.document.body!.appendChild(host);
  host.appendChild(canvas);
  return canvas;
}

void _removeCanvasHost(web.HTMLCanvasElement canvas) {
  final host = canvas.parentElement;
  canvas.remove();
  host?.remove();
}

web.HTMLCanvasElement _createCanvas({
  required int logicalWidth,
  required int logicalHeight,
  required int backingWidth,
  required int backingHeight,
}) => web.HTMLCanvasElement()
  ..width = backingWidth
  ..height = backingHeight
  ..style.width = '${logicalWidth}px'
  ..style.height = '${logicalHeight}px'
  ..style.position = 'absolute';

@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:mixpanel_flutter_session_replay/src/internal/capture/rendered_surface_capture.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/platform/web_rendered_surface_capture.dart';
import 'dart:ui' show Rect, Size;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:web/web.dart' as web;

void main() {
  for (final backing in [
    const Size(240, 160), // Uniform 2x density.
    const Size(240, 80), // Twice the CSS aspect ratio.
    const Size(120, 160), // Half the CSS aspect ratio.
    const Size(241, 159), // Fractional-density rounding.
  ]) {
    test(
      'masks align with displayed pixels for $backing backing size',
      () async {
        // GIVEN content displayed at a known logical position, regardless of
        // the backing store's independent horizontal and vertical resolution
        const logicalSize = Size(120, 80);
        const sensitive = Rect.fromLTWH(72, 24, 32, 32);
        final canvas = _appendCanvas(
          logicalWidth: 120,
          logicalHeight: 80,
          backingWidth: backing.width.toInt(),
          backingHeight: backing.height.toInt(),
        );
        addTearDown(() => _removeCanvasHost(canvas));
        final context =
            canvas.getContext('2d')! as web.CanvasRenderingContext2D;
        context.scale(
          backing.width / logicalSize.width,
          backing.height / logicalSize.height,
        );
        context.fillStyle = '#ffffff'.toJS;
        context.fillRect(0, 0, logicalSize.width, logicalSize.height);
        context.fillStyle = '#ff0000'.toJS;
        context.fillRect(
          sensitive.left,
          sensitive.top,
          sensitive.width,
          sensitive.height,
        );
        final capture = WebRenderedSurfaceCapture(
          logger: MixpanelLogger(LogLevel.none),
          jpegQuality: 1,
        );
        addTearDown(capture.dispose);
        await capture.initialize();

        // WHEN pixels and mask coordinates are downscaled to half logical size
        final unmasked = img.decodeJpg(
          (await _captureAndEncode(
            capture,
            logicalSize: logicalSize,
            outputWidth: 60,
            outputHeight: 40,
          ))!,
        )!;
        final masked = img.decodeJpg(
          (await _captureAndEncode(
            capture,
            logicalSize: logicalSize,
            outputWidth: 60,
            outputHeight: 40,
            maskRects: [
              Rect.fromLTRB(
                sensitive.left / 2,
                sensitive.top / 2,
                sensitive.right / 2,
                sensitive.bottom / 2,
              ),
            ],
          ))!,
        )!;

        // THEN the control contains real sensitive pixels and masking removes
        // them at the correct output coordinates, even with a mismatched ratio
        int sensitivePixels(img.Image image) => image
            .where((pixel) => pixel.r > 180 && pixel.g < 80 && pixel.b < 80)
            .length;
        expect(sensitivePixels(unmasked), greaterThan(100));
        expect(sensitivePixels(masked), 0);
        final center = masked.getPixel(44, 20);
        expect(center.r, closeTo(204, 8));
        expect(center.g, closeTo(204, 8));
        expect(center.b, closeTo(204, 8));
        final outside = masked.getPixel(10, 10);
        expect(outside.r, greaterThan(240));
        expect(outside.g, greaterThan(240));
        expect(outside.b, greaterThan(240));
      },
    );
  }

  test('hiding during the post-snapshot wait closes the bitmap', () async {
    // GIVEN a visible page and a real captured bitmap
    var hidden = false;
    (globalContext['Object'] as JSObject).callMethod(
      'defineProperty'.toJS,
      web.document,
      'hidden'.toJS,
      {'get': (() => hidden).toJS, 'configurable': true}.jsify(),
    );
    addTearDown(() => web.document.delete('hidden'.toJS));
    final canvas = _appendCanvas(
      logicalWidth: 73,
      logicalHeight: 51,
      backingWidth: 73,
      backingHeight: 51,
    );
    addTearDown(() => _removeCanvasHost(canvas));
    final capture = WebRenderedSurfaceCapture(
      logger: MixpanelLogger(LogLevel.none),
    );
    addTearDown(capture.dispose);
    await capture.initialize();
    final bitmap = await web.window.createImageBitmap(canvas).toDart;
    addTearDown(() => bitmap.close());
    final originalCreate = (web.window as JSObject)['createImageBitmap'];
    (web.window as JSObject)['createImageBitmap'] =
        ((JSAny source, JSAny options) => Future.value(bitmap).toJS).toJS;
    addTearDown(
      () => (web.window as JSObject)['createImageBitmap'] = originalCreate,
    );

    // WHEN the page hides while its animation callback is suspended
    final originalRequest = (web.window as JSObject)['requestAnimationFrame'];
    final originalCancel = (web.window as JSObject)['cancelAnimationFrame'];
    addTearDown(() {
      (web.window as JSObject)['requestAnimationFrame'] = originalRequest;
      (web.window as JSObject)['cancelAnimationFrame'] = originalCancel;
    });
    var cancelled = false;
    (web.window as JSObject)['requestAnimationFrame'] = ((JSFunction callback) {
      scheduleMicrotask(() {
        hidden = true;
        web.document.dispatchEvent(web.Event('visibilitychange'));
      });
      return 123;
    }).toJS;
    (web.window as JSObject)['cancelAnimationFrame'] = ((int id) {
      cancelled = id == 123;
    }).toJS;
    final result = await capture
        .capture(
          logicalSize: const Size(73, 51),
          outputWidth: 73,
          outputHeight: 51,
        )
        .timeout(const Duration(seconds: 1));

    // THEN capture finishes without a browser frame and releases its bitmap
    expect(result, isNull);
    expect(cancelled, isTrue);
    expect(bitmap.width, 0);
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
      final compressor = WebRenderedSurfaceCapture(
        logger: MixpanelLogger(LogLevel.none),
        jpegQuality: 1,
      );
      addTearDown(compressor.dispose);
      await compressor.initialize();

      // When the browser surface is resized entirely inside the worker.
      final result = await _captureAndEncode(
        compressor,
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
    final compressor = WebRenderedSurfaceCapture(
      logger: MixpanelLogger(LogLevel.none),
      jpegQuality: 1,
    );
    addTearDown(compressor.dispose);
    await compressor.initialize();

    // When a partial privacy mask is supplied in output coordinates.
    final result = await _captureAndEncode(
      compressor,
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
      final compressor = WebRenderedSurfaceCapture(
        logger: MixpanelLogger(LogLevel.none),
      );
      addTearDown(compressor.dispose);
      await compressor.initialize();

      // When capture cannot identify a unique source surface.
      final result = await _captureAndEncode(
        compressor,
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

    final compressor = WebRenderedSurfaceCapture(
      logger: MixpanelLogger(LogLevel.none),
      jpegQuality: 1,
    );
    addTearDown(compressor.dispose);
    await compressor.initialize();

    final result = await _captureAndEncode(
      compressor,
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
    final compressor = WebRenderedSurfaceCapture(
      logger: MixpanelLogger(LogLevel.none),
    );
    addTearDown(compressor.dispose);
    await compressor.initialize();

    final result = await _captureAndEncode(
      compressor,
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
      final compressor = WebRenderedSurfaceCapture(
        logger: MixpanelLogger(LogLevel.none),
      );
      addTearDown(compressor.dispose);
      await compressor.initialize();

      final portrait = await _captureAndEncode(
        compressor,
        logicalSize: const Size(53, 39),
        outputWidth: 27,
        outputHeight: 20,
      );
      canvas
        ..width = 78
        ..height = 106
        ..style.width = '39px'
        ..style.height = '53px';
      final landscape = await _captureAndEncode(
        compressor,
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
      final compressor = WebRenderedSurfaceCapture(
        logger: MixpanelLogger(LogLevel.none),
      );
      addTearDown(compressor.dispose);
      await compressor.initialize();

      final result = await _captureAndEncode(
        compressor,
        logicalSize: const Size(8765, 4321),
        outputWidth: 10,
        outputHeight: 10,
      );

      expect(result, isNull);
      expect(compressor.isAvailable, isTrue);
    },
  );

  test('an ambiguous surface fails fast instead of polling frames', () async {
    // GIVEN two Flutter views, which no amount of waiting can disambiguate
    final firstView = web.document.createElement('flutter-view');
    final secondView = web.document.createElement('flutter-view');
    web.document.body!
      ..appendChild(firstView)
      ..appendChild(secondView);
    addTearDown(() => firstView.remove());
    addTearDown(() => secondView.remove());
    final compressor = WebRenderedSurfaceCapture(
      logger: MixpanelLogger(LogLevel.none),
    );
    addTearDown(compressor.dispose);
    await compressor.initialize();

    // WHEN surface discovery runs
    final watch = Stopwatch()..start();
    final availability = await compressor.waitUntilRenderedSurfaceAvailable(
      const Size(59, 41),
    );

    // THEN it gives up immediately rather than spending ~30 browser frames
    // of forced layout on every capture attempt
    expect(availability, RenderedSurfaceAvailability.unavailable);
    expect(watch.elapsedMilliseconds, lessThan(200));
  });

  test('waits for a mounted canvas to publish its first rendered size', () async {
    // GIVEN skwasm has mounted a canvas but has not rasterized its first frame.
    final canvas = _appendCanvas(
      logicalWidth: 0,
      logicalHeight: 0,
      backingWidth: 300,
      backingHeight: 150,
    );
    canvas.getContext('2d');
    addTearDown(() => _removeCanvasHost(canvas));
    final surface = WebRenderedSurfaceCapture(
      logger: MixpanelLogger(LogLevel.none),
    );
    addTearDown(surface.dispose);
    await surface.initialize();

    // WHEN first presentation takes longer than the two-frame resize window.
    var frames = 0;
    var callbackId = 0;
    void publishAfterFrames(num _) {
      if (++frames == 5) {
        canvas.style
          ..width = '59px'
          ..height = '41px';
      } else {
        callbackId = web.window.requestAnimationFrame(publishAfterFrames.toJS);
      }
    }

    callbackId = web.window.requestAnimationFrame(publishAfterFrames.toJS);
    addTearDown(() => web.window.cancelAnimationFrame(callbackId));
    final availability = await surface.waitUntilRenderedSurfaceAvailable(
      const Size(59, 41),
    );

    // THEN an unpainted canvas receives the bounded cold-start wait.
    expect(
      availability,
      RenderedSurfaceAvailability.availableAfterBrowserFrame,
    );
  });

  test('two same-sized canvases fail fast', () async {
    final first = _appendCanvas(
      logicalWidth: 59,
      logicalHeight: 41,
      backingWidth: 59,
      backingHeight: 41,
    );
    final second = _appendCanvas(
      logicalWidth: 59,
      logicalHeight: 41,
      backingWidth: 59,
      backingHeight: 41,
    );
    addTearDown(() => _removeCanvasHost(first));
    addTearDown(() => _removeCanvasHost(second));
    final compressor = WebRenderedSurfaceCapture(
      logger: MixpanelLogger(LogLevel.none),
    );
    addTearDown(compressor.dispose);
    await compressor.initialize();

    final watch = Stopwatch()..start();
    final availability = await compressor.waitUntilRenderedSurfaceAvailable(
      const Size(59, 41),
    );

    expect(availability, RenderedSurfaceAvailability.unavailable);
    expect(watch.elapsedMilliseconds, lessThan(200));
  });

  test('a skipped capture is logged once per cause', () async {
    // GIVEN a warning-level logger whose records are observable
    final records = <LogRecord>[];
    final subscription = Logger(
      'mixpanel.session_replay',
    ).onRecord.listen(records.add);
    addTearDown(subscription.cancel);
    final firstView = web.document.createElement('flutter-view');
    final secondView = web.document.createElement('flutter-view');
    web.document.body!
      ..appendChild(firstView)
      ..appendChild(secondView);
    addTearDown(() => firstView.remove());
    addTearDown(() => secondView.remove());
    final compressor = WebRenderedSurfaceCapture(
      logger: MixpanelLogger(LogLevel.warning),
    );
    addTearDown(compressor.dispose);
    await compressor.initialize();

    // WHEN several capture attempts hit the same ambiguous layout
    await compressor.waitUntilRenderedSurfaceAvailable(const Size(59, 41));
    await compressor.waitUntilRenderedSurfaceAvailable(const Size(59, 41));
    await compressor.waitUntilRenderedSurfaceAvailable(const Size(59, 41));

    // THEN the developer sees one warning, not one per frame
    final skips = records.where(
      (record) =>
          record.level == Level.WARNING &&
          record.message.contains('Web capture skipped'),
    );
    expect(skips, hasLength(1));
  });

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
    final compressor = WebRenderedSurfaceCapture(
      logger: MixpanelLogger(LogLevel.none),
    );
    addTearDown(compressor.dispose);
    await compressor.initialize();

    final result = await _captureAndEncode(
      compressor,
      logicalSize: const Size(59, 41),
      outputWidth: 59,
      outputHeight: 41,
    );

    expect(result, isNull);
  });

  test(
    'captures a platform-view page when it still has a single canvas',
    () async {
      // GIVEN - a platform view's pixels live in a DOM node, so they are never
      // in the canvas backing store; its presence must not alter the capture
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
      final compressor = WebRenderedSurfaceCapture(
        logger: MixpanelLogger(LogLevel.none),
        jpegQuality: 1,
      );
      addTearDown(compressor.dispose);
      await compressor.initialize();

      final result = await _captureAndEncode(
        compressor,
        logicalSize: const Size(63, 45),
        outputWidth: 63,
        outputHeight: 45,
      );

      final pixel = img.decodeJpg(result!)!.getPixel(31, 22);
      expect(pixel.r, greaterThan(240));
      expect(pixel.g, lessThan(15));
      expect(pixel.b, lessThan(15));
    },
  );

  test(
    'skips a platform-view composition split across canvases and recovers',
    () async {
      // GIVEN one Flutter engine host with two full-size rendering surfaces.
      final first = _appendCanvas(
        logicalWidth: 65,
        logicalHeight: 47,
        backingWidth: 65,
        backingHeight: 47,
      );
      addTearDown(() => _removeCanvasHost(first));
      final second = _createCanvas(
        logicalWidth: 65,
        logicalHeight: 47,
        backingWidth: 65,
        backingHeight: 47,
      );
      first.parentNode!.appendChild(second);
      final platformView = web.document.createElement('flt-platform-view');
      first.parentNode!.appendChild(platformView);
      final capture = WebRenderedSurfaceCapture(
        logger: MixpanelLogger(LogLevel.none),
      );
      await capture.initialize();
      addTearDown(capture.dispose);

      // WHEN the platform view forces an ambiguous composition.
      expect(
        await capture.capture(
          logicalSize: const Size(65, 47),
          outputWidth: 65,
          outputHeight: 47,
        ),
        isNull,
      );

      // THEN capture becomes available again when the extra surface is removed.
      second.remove();
      final snapshot = await capture.capture(
        logicalSize: const Size(65, 47),
        outputWidth: 65,
        outputHeight: 47,
      );
      expect(snapshot, isNotNull);
      snapshot!.dispose();
      expect(await snapshot.encode(maskRects: const []), isNull);
    },
  );

  test('a captured frame can be encoded only once', () async {
    final canvas = _appendCanvas(
      logicalWidth: 69,
      logicalHeight: 47,
      backingWidth: 69,
      backingHeight: 47,
    );
    addTearDown(() => _removeCanvasHost(canvas));
    final capture = WebRenderedSurfaceCapture(
      logger: MixpanelLogger(LogLevel.none),
    );
    await capture.initialize();
    addTearDown(capture.dispose);
    final snapshot = await capture.capture(
      logicalSize: const Size(69, 47),
      outputWidth: 69,
      outputHeight: 47,
    );
    expect(snapshot, isNotNull);
    expect(await snapshot!.encode(maskRects: const []), isNotNull);
    expect(await snapshot.encode(maskRects: const []), isNull);
    snapshot.dispose();
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
    final compressor = WebRenderedSurfaceCapture(
      logger: MixpanelLogger(LogLevel.none),
      jpegQuality: 1,
    );
    addTearDown(compressor.dispose);
    await compressor.initialize();

    final result = await _captureAndEncode(
      compressor,
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
    final compressor = WebRenderedSurfaceCapture(
      logger: MixpanelLogger(LogLevel.none),
    );
    addTearDown(compressor.dispose);
    await compressor.initialize();
    var validationCalls = 0;

    final result = await _captureAndEncode(
      compressor,
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

Future<Uint8List?> _captureAndEncode(
  WebRenderedSurfaceCapture capture, {
  required Size logicalSize,
  required int outputWidth,
  required int outputHeight,
  List<Rect> maskRects = const [],
  bool Function()? validateSnapshot,
}) async {
  final snapshot = await capture.capture(
    logicalSize: logicalSize,
    outputWidth: outputWidth,
    outputHeight: outputHeight,
  );
  if (snapshot == null) return null;
  try {
    if (validateSnapshot != null && !validateSnapshot()) return null;
    return await snapshot.encode(maskRects: maskRects);
  } finally {
    snapshot.dispose();
  }
}

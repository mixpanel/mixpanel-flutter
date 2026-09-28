import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;
import 'package:web/web.dart' as web;
import '../capture/rendered_surface_capture.dart';
import '../logger.dart';
import 'web_image_compressor.dart';

/// Discovers Flutter's single rendering surface and acquires immutable frames.
/// Ambiguous multi-canvas/multi-view compositions are skipped in their entirety.
class WebRenderedSurfaceCapture extends RenderedSurfaceCapture {
  static const _engineSurfaceHostSelector =
      'flutter-view, flt-glass-pane, flt-scene-host, flt-renderer';
  final MixpanelLogger _logger;
  final WebImageCompressor _encoder;
  WebImageCaptureTimings? lastCaptureTimings;

  WebRenderedSurfaceCapture({
    required MixpanelLogger logger,
    double jpegQuality = 0.8,
  }) : _logger = logger,
       _encoder = WebImageCompressor(logger: logger, jpegQuality: jpegQuality);

  Future<void> initialize() => _encoder.initialize();
  @override
  bool get isAvailable => _encoder.isAvailable;

  @override
  Future<RenderedSurfaceAvailability> waitUntilRenderedSurfaceAvailable(
    Size logicalSize,
  ) async {
    if (_matchingCanvases(logicalSize).length == 1) {
      return RenderedSurfaceAvailability.available;
    }
    // Wasm can publish its visible canvas several browser frames after the
    // first Flutter frame on cold startup. This is surface discovery only;
    // ScreenshotCapturer establishes a fresh Flutter end-of-frame afterward.
    for (var attempt = 0; attempt < 30; attempt++) {
      await _nextAnimationFrame();
      if (_matchingCanvases(logicalSize).length == 1) {
        return RenderedSurfaceAvailability.availableAfterBrowserFrame;
      }
    }
    return RenderedSurfaceAvailability.unavailable;
  }

  static Future<void> _nextAnimationFrame() {
    final completer = Completer<void>();
    void onFrame(num _) => completer.complete();
    web.window.requestAnimationFrame(onFrame.toJS);
    return completer.future;
  }

  @override
  Future<void> waitForRenderedSurfacePresentation() => _nextAnimationFrame();

  @override
  Future<CapturedSurface?> capture({
    required Size logicalSize,
    required int outputWidth,
    required int outputHeight,
  }) async {
    if (!isAvailable) return null;

    final captureWatch = Stopwatch()..start();
    final matchingCanvases = _matchingCanvases(logicalSize);
    final surfaceLookup = captureWatch.elapsed;
    if (matchingCanvases.length != 1) {
      final available = _flutterCanvases()
          .map((canvas) {
            final bounds = canvas.getBoundingClientRect();
            return '${bounds.width}x${bounds.height} CSS '
                '(${canvas.width}x${canvas.height} backing)';
          })
          .join(', ');
      _logger.warning(
        matchingCanvases.isEmpty
            ? 'Web capture skipped: no Flutter canvas matches '
                  '${logicalSize.width}x${logicalSize.height}; available: '
                  '${available.isEmpty ? 'none' : available}'
            : 'Web capture skipped: ${matchingCanvases.length} canvases match '
                  '${logicalSize.width}x${logicalSize.height}, so the source '
                  'surface is ambiguous',
      );
      return null;
    }

    web.ImageBitmap? imageBitmap;
    try {
      imageBitmap = await web.window
          .createImageBitmap(
            matchingCanvases.single,
            web.ImageBitmapOptions(
              resizeWidth: outputWidth,
              resizeHeight: outputHeight,
              resizeQuality: 'high',
            ),
          )
          .toDart;
      final bitmapCreation = captureWatch.elapsed - surfaceLookup;
      // Preserve the existing post-snapshot presentation opportunity. The
      // immutable bitmap stays local until ScreenshotCapturer validates masks.
      await _nextAnimationFrame();
      if (!isAvailable) return null;
      final snapshot = _WebCapturedSurface(
        imageBitmap,
        _encoder,
        outputWidth,
        outputHeight,
        (workerProcessing) {
          lastCaptureTimings = WebImageCaptureTimings(
            surfaceLookup: surfaceLookup,
            bitmapCreation: bitmapCreation,
            snapshotValidation:
                captureWatch.elapsed -
                surfaceLookup -
                bitmapCreation -
                workerProcessing,
            workerProcessing: workerProcessing,
          );
        },
      );
      imageBitmap = null; // Ownership passed to the snapshot.
      return snapshot;
    } catch (error) {
      _logger.warning(
        'Web surface capture failed; dropping this frame: $error',
      );
      return null;
    } finally {
      imageBitmap?.close();
    }
  }

  static List<web.HTMLCanvasElement> _matchingCanvases(Size logicalSize) {
    const tolerance = 2.0;
    return _flutterCanvases()
        .where((canvas) {
          final bounds = canvas.getBoundingClientRect();
          return (bounds.width - logicalSize.width).abs() <= tolerance &&
              (bounds.height - logicalSize.height).abs() <= tolerance &&
              bounds.width > 0 &&
              bounds.height > 0;
        })
        .toList(growable: false);
  }

  /// Returns only canvases contained by a known Flutter engine surface host.
  ///
  /// Restricting lookup to these small subtrees avoids both capturing an
  /// unrelated page canvas and recursively walking the full document. A new
  /// renderer structure therefore fails closed until its ownership can be
  /// identified explicitly.
  static List<web.HTMLCanvasElement> _flutterCanvases() {
    final canvases = <web.HTMLCanvasElement>[];
    var flutterViewCount = 0;
    var glassPaneCount = 0;

    void addCanvases(web.NodeList matches) {
      for (var index = 0; index < matches.length; index++) {
        final canvas = matches.item(index) as web.HTMLCanvasElement?;
        if (canvas != null && !canvases.contains(canvas)) {
          canvases.add(canvas);
        }
      }
    }

    final hosts = web.document.querySelectorAll(_engineSurfaceHostSelector);
    for (var index = 0; index < hosts.length; index++) {
      final host = hosts.item(index) as web.Element?;
      if (host != null) {
        if (host.localName == 'flutter-view') flutterViewCount++;
        if (host.localName == 'flt-glass-pane') glassPaneCount++;
        addCanvases(host.querySelectorAll('canvas'));
        final shadowRoot = _shadowRoot(host);
        if (shadowRoot != null) {
          addCanvases(shadowRoot.querySelectorAll('canvas'));
        }
      }
    }
    if (flutterViewCount > 1 || glassPaneCount > 1) return const [];
    return canvases;
  }

  static web.ShadowRoot? _shadowRoot(web.Element? host) =>
      host?.getProperty('shadowRoot'.toJS);

  @override
  Future<void> dispose() => _encoder.dispose();
}

class _WebCapturedSurface implements CapturedSurface {
  web.ImageBitmap? _bitmap;
  final WebImageCompressor _encoder;
  final int _width;
  final int _height;
  final void Function(Duration) _onEncoded;

  _WebCapturedSurface(
    this._bitmap,
    this._encoder,
    this._width,
    this._height,
    this._onEncoded,
  );

  @override
  Future<Uint8List?> encode({required List<Rect> maskRects}) async {
    final bitmap = _bitmap;
    if (bitmap == null) return null;
    _bitmap = null;
    final watch = Stopwatch()..start();
    final result = await _encoder.compressBitmap(
      imageBitmap: bitmap,
      width: _width,
      height: _height,
      maskRects: maskRects,
    );
    _onEncoded(watch.elapsed);
    return result;
  }

  @override
  void dispose() {
    _bitmap?.close();
    _bitmap = null;
  }
}

class WebImageCaptureTimings {
  const WebImageCaptureTimings({
    required this.surfaceLookup,
    required this.bitmapCreation,
    required this.snapshotValidation,
    required this.workerProcessing,
  });

  final Duration surfaceLookup;
  final Duration bitmapCreation;
  final Duration snapshotValidation;
  final Duration workerProcessing;

  Map<String, int> toMillisecondsJson() => {
    'surface_lookup_ms': surfaceLookup.inMilliseconds,
    'bitmap_creation_ms': bitmapCreation.inMilliseconds,
    'snapshot_validation_window_ms': snapshotValidation.inMilliseconds,
    'worker_processing_ms': workerProcessing.inMilliseconds,
  };
}

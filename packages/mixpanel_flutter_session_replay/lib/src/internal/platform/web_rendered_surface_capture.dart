import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;
import 'package:web/web.dart' as web;
import '../capture/rendered_surface_capture.dart';
import '../logger.dart';
import 'web_jpeg_encoder.dart';

/// Discovers Flutter's single rendering surface and acquires immutable frames.
/// Ambiguous multi-canvas/multi-view compositions are skipped in their entirety.
class WebRenderedSurfaceCapture extends RenderedSurfaceCapture {
  static const _engineSurfaceHostSelector =
      'flutter-view, flt-glass-pane, flt-scene-host, flt-renderer';
  final MixpanelLogger _logger;
  final WebJpegEncoder _encoder;
  WebImageCaptureTimings? lastCaptureTimings;

  /// Browser frames to wait for a surface that has not been published yet.
  /// Wasm can publish its visible canvas several frames after the first
  /// Flutter frame on cold startup.
  static const _coldStartFrames = 30;

  /// Browser frames to wait for an existing canvas to match the boundary
  /// size, covering a resize that has not reached the DOM yet.
  static const _resizeFrames = 2;

  /// Why the last capture was skipped, so the diagnostic is logged once per
  /// distinct cause rather than once per frame while the layout persists.
  String? _lastSkipReason;

  WebRenderedSurfaceCapture({
    required MixpanelLogger logger,
    double jpegQuality = 0.8,
  }) : _logger = logger,
       _encoder = WebJpegEncoder(logger: logger, jpegQuality: jpegQuality);

  Future<void> initialize() => _encoder.initialize();
  @override
  bool get isAvailable => _encoder.isAvailable;

  @override
  Future<RenderedSurfaceAvailability> waitUntilRenderedSurfaceAvailable(
    Size logicalSize,
  ) async {
    var lookup = _SurfaceLookup.of(logicalSize);
    if (lookup.isReady) {
      _lastSkipReason = null;
      return RenderedSurfaceAvailability.available;
    }
    // Only a surface that may still appear is worth waiting for. An ambiguous
    // layout (several matching canvases, or several Flutter views) will not
    // resolve by waiting, and polling it on every capture attempt would cost
    // dozens of forced layouts per frame for as long as it persists. This is
    // surface discovery only; ScreenshotCapturer establishes a fresh Flutter
    // end-of-frame afterward.
    if (!lookup.isAmbiguous) {
      final attempts = lookup.hasNoCanvas ? _coldStartFrames : _resizeFrames;
      for (var attempt = 0; attempt < attempts; attempt++) {
        await _nextAnimationFrame();
        lookup = _SurfaceLookup.of(logicalSize);
        if (lookup.isReady) {
          _lastSkipReason = null;
          return RenderedSurfaceAvailability.availableAfterBrowserFrame;
        }
        if (lookup.isAmbiguous) break;
      }
    }
    _reportSkip(lookup.describeSkip(logicalSize));
    return RenderedSurfaceAvailability.unavailable;
  }

  /// Logs a skipped capture once per distinct cause. Capture is attempted on
  /// every scheduled frame, so repeating it would flood the console while a
  /// platform view or second Flutter view stays on screen.
  void _reportSkip(String reason) {
    if (reason == _lastSkipReason) return;
    _lastSkipReason = reason;
    _logger.warning(reason);
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
    final lookup = _SurfaceLookup.of(logicalSize);
    final surfaceLookup = captureWatch.elapsed;
    if (!lookup.isReady) {
      _reportSkip(lookup.describeSkip(logicalSize));
      return null;
    }
    final matchingCanvases = lookup.matches;

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

  static web.ShadowRoot? _shadowRoot(web.Element? host) =>
      host?.getProperty('shadowRoot'.toJS);

  @override
  Future<void> dispose() => _encoder.dispose();
}

/// One inspection of the DOM for Flutter's rendering surface.
class _SurfaceLookup {
  const _SurfaceLookup._({
    required this.canvases,
    required this.matches,
    required this.hasMultipleViews,
  });

  factory _SurfaceLookup.of(Size logicalSize) {
    const tolerance = 2.0;
    final (canvases, hasMultipleViews) = _flutterCanvases();
    final matches = canvases
        .where((canvas) {
          final bounds = canvas.getBoundingClientRect();
          return (bounds.width - logicalSize.width).abs() <= tolerance &&
              (bounds.height - logicalSize.height).abs() <= tolerance &&
              bounds.width > 0 &&
              bounds.height > 0;
        })
        .toList(growable: false);
    return _SurfaceLookup._(
      canvases: canvases,
      matches: matches,
      hasMultipleViews: hasMultipleViews,
    );
  }

  /// Every canvas under a Flutter engine surface host.
  final List<web.HTMLCanvasElement> canvases;

  /// The canvases whose CSS size matches the capture boundary.
  final List<web.HTMLCanvasElement> matches;

  /// More than one Flutter view or glass pane is mounted.
  final bool hasMultipleViews;

  bool get isReady => !hasMultipleViews && matches.length == 1;

  /// Waiting cannot resolve this layout.
  bool get isAmbiguous => hasMultipleViews || matches.length > 1;

  /// No Flutter canvas has been published yet.
  bool get hasNoCanvas => canvases.isEmpty;

  String describeSkip(Size logicalSize) {
    final size = '${logicalSize.width}x${logicalSize.height}';
    if (hasMultipleViews) {
      return 'Web capture skipped: more than one Flutter view is mounted, so '
          'the source surface is ambiguous';
    }
    if (matches.length > 1) {
      return 'Web capture skipped: ${matches.length} canvases match $size, so '
          'the source surface is ambiguous';
    }
    final available = canvases
        .map((canvas) {
          final bounds = canvas.getBoundingClientRect();
          return '${bounds.width}x${bounds.height} CSS '
              '(${canvas.width}x${canvas.height} backing)';
        })
        .join(', ');
    return 'Web capture skipped: no Flutter canvas matches $size; available: '
        '${available.isEmpty ? 'none' : available}';
  }

  /// Returns the canvases contained by a known Flutter engine surface host,
  /// and whether more than one Flutter view or glass pane is mounted.
  ///
  /// Restricting lookup to these small subtrees avoids both capturing an
  /// unrelated page canvas and recursively walking the full document. A new
  /// renderer structure therefore fails closed until its ownership can be
  /// identified explicitly.
  static (List<web.HTMLCanvasElement>, bool) _flutterCanvases() {
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

    final hosts = web.document.querySelectorAll(
      WebRenderedSurfaceCapture._engineSurfaceHostSelector,
    );
    for (var index = 0; index < hosts.length; index++) {
      final host = hosts.item(index) as web.Element?;
      if (host != null) {
        if (host.localName == 'flutter-view') flutterViewCount++;
        if (host.localName == 'flt-glass-pane') glassPaneCount++;
        addCanvases(host.querySelectorAll('canvas'));
        final shadowRoot = WebRenderedSurfaceCapture._shadowRoot(host);
        if (shadowRoot != null) {
          addCanvases(shadowRoot.querySelectorAll('canvas'));
        }
      }
    }
    return (canvases, flutterViewCount > 1 || glassPaneCount > 1);
  }
}

class _WebCapturedSurface implements CapturedSurface {
  web.ImageBitmap? _bitmap;
  final WebJpegEncoder _encoder;
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
    final result = await _encoder.encode(
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

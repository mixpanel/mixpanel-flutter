import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;
import 'package:flutter/foundation.dart' show kIsWasm;
import 'package:flutter/scheduler.dart';
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

  // CanvasKit uses an on-screen WebGL context on Safari and Firefox.
  // Without preserveDrawingBuffer, its pixels expire after presentation.
  bool _requiresSameFrameSnapshot = false;

  /// A copy of the WebGL surface taken inside the frame callback that drew it.
  ///
  /// The drawing buffer is discarded as soon as that task yields, and the mask
  /// walk plus `createImageBitmap` both run afterwards, so reading the live
  /// canvas in [capture] returns a cleared — black — surface whenever anything
  /// in between crosses a macrotask boundary. Copying into a 2D canvas while
  /// still inside the frame callback makes the pixels stable for the rest of
  /// the pipeline. Only browsers that need it pay for the copy.
  web.HTMLCanvasElement? _frameSnapshot;

  /// Whether [_frameSnapshot] holds pixels for the capture now in flight.
  bool _frameSnapshotIsFresh = false;

  /// Frames Flutter has drawn, counted here because
  /// `SchedulerBinding.currentFrameTimeStamp` asserts outside a frame and the
  /// copy runs in a browser callback after the frame has ended.
  ///
  /// Static because the callback below can never be removed: an instance field
  /// would make the closure capture `this`, pinning every disposed capture and
  /// adding a second callback each time replay reinitializes. Only equality
  /// between two reads of this counter matters, so one shared count is enough.
  static int _framesPainted = 0;
  static bool _frameCounterArmed = false;

  /// The value of [_framesPainted] when the copy was taken.
  ///
  /// ScreenshotCapturer awaits another painted frame before walking masks
  /// whenever one is already scheduled, so an animation can move a masked
  /// widget between the copy and the mask read. The masks would then describe
  /// a frame these pixels are not from, and a mask could land beside the
  /// content it is meant to cover. Captures are dropped rather than encoded
  /// when that happens.
  int? _frameSnapshotFrame;

  /// Set by [dispose] so a frame callback already queued cannot allocate a new
  /// snapshot canvas after cleanup released the old one.
  bool _isDisposed = false;

  /// How long the last in-frame copy took. Measured because it runs inside the
  /// animation frame callback, where overruns cost a presented frame, and it
  /// is the one cost this strategy adds on WebGL surfaces.
  Duration _lastFrameSnapshot = Duration.zero;

  WebRenderedSurfaceCapture({
    required MixpanelLogger logger,
    double jpegQuality = 0.8,
  }) : _logger = logger,
       _encoder = WebJpegEncoder(logger: logger, jpegQuality: jpegQuality);

  Future<void> initialize() => _encoder.initialize();

  /// Armed only on the WebGL path, which already requires the binding to
  /// schedule a frame. Surfaces that never copy do not touch the scheduler.
  void _armFrameCounter() {
    if (_frameCounterArmed) return;
    _frameCounterArmed = true;
    // Persistent callbacks cannot be removed, so this closure must stay free
    // of instance state; it touches only the static counter above.
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      _framesPainted++;
    });
  }

  @override
  bool get isAvailable => _encoder.isAvailable;

  @override
  Future<RenderedSurfaceAvailability> waitUntilRenderedSurfaceAvailable(
    Size logicalSize, {
    Size? captureExtent,
  }) async {
    if (web.document.hidden) return RenderedSurfaceAvailability.unavailable;
    var lookup = _SurfaceLookup.of(logicalSize);
    if (lookup.isReady) {
      _lastSkipReason = null;
      return _prepareReadableSurface(
        lookup.matches.single,
        captureExtent ?? logicalSize,
      );
    }
    // Only a surface that may still appear is worth waiting for. An ambiguous
    // layout (several matching canvases, or several Flutter views) will not
    // resolve by waiting, and polling it on every capture attempt would cost
    // dozens of forced layouts per frame for as long as it persists. This is
    // surface discovery only; ScreenshotCapturer establishes a fresh Flutter
    // end-of-frame afterward.
    if (!lookup.isAmbiguous) {
      final attempts = lookup.hasNoVisibleCanvas
          ? _coldStartFrames
          : _resizeFrames;
      for (var attempt = 0; attempt < attempts; attempt++) {
        if (!await _nextAnimationFrame()) {
          return RenderedSurfaceAvailability.unavailable;
        }
        lookup = _SurfaceLookup.of(logicalSize);
        if (lookup.isReady) {
          _lastSkipReason = null;
          final availability = await _prepareReadableSurface(
            lookup.matches.single,
            captureExtent ?? logicalSize,
          );
          if (availability == RenderedSurfaceAvailability.unavailable) {
            return availability;
          }
          return RenderedSurfaceAvailability.availableAfterBrowserFrame;
        }
        if (lookup.isAmbiguous) break;
      }
    }
    _reportSkip(lookup.describeSkip(logicalSize));
    return RenderedSurfaceAvailability.unavailable;
  }

  Future<RenderedSurfaceAvailability> _prepareReadableSurface(
    web.HTMLCanvasElement canvas,
    Size logicalSize,
  ) async {
    _requiresSameFrameSnapshot =
        !kIsWasm &&
        (canvas.getContext('webgl2') != null ||
            canvas.getContext('webgl') != null);
    if (_requiresSameFrameSnapshot) {
      _armFrameCounter();
      // Register after Flutter's requested frame so rasterization runs before
      // this callback, but snapshot before the browser clears the WebGL buffer.
      // This must happen before the mask walk: requesting a frame afterward
      // would perpetually re-arm the capture scheduler on a static screen.
      SchedulerBinding.instance.scheduleFrame();
      if (!await _snapshotWithinAnimationFrame(canvas, logicalSize)) {
        return RenderedSurfaceAvailability.unavailable;
      }
      return RenderedSurfaceAvailability.availableAfterBrowserFrame;
    }
    return RenderedSurfaceAvailability.available;
  }

  /// Logs a skipped capture once per distinct cause. Capture is attempted on
  /// every scheduled frame, so repeating it would flood the console while a
  /// platform view or second Flutter view stays on screen.
  void _reportSkip(String reason) {
    if (reason == _lastSkipReason) return;
    _lastSkipReason = reason;
    _logger.warning(reason);
  }

  /// Copies [canvas] into [_frameSnapshot] from inside the animation frame
  /// callback, so no task boundary separates the rasterized buffer from the
  /// read. Awaiting the frame and copying afterwards is not equivalent: the
  /// resumption is a microtask on some engines and a macrotask on others, and
  /// the buffer is already gone in the latter case.
  Future<bool> _snapshotWithinAnimationFrame(
    web.HTMLCanvasElement canvas,
    Size logicalSize,
  ) {
    _frameSnapshotIsFresh = false;
    _frameSnapshotFrame = null;
    if (_isDisposed || web.document.hidden) return Future.value(false);
    final completer = Completer<bool>();
    late final int frameId;
    late final JSFunction onVisibilityChange;
    void finish(bool captured) {
      if (completer.isCompleted) return;
      web.window.cancelAnimationFrame(frameId);
      web.document.removeEventListener('visibilitychange', onVisibilityChange);
      completer.complete(captured);
    }

    onVisibilityChange = ((web.Event _) {
      if (web.document.hidden) finish(false);
    }).toJS;
    web.document.addEventListener('visibilitychange', onVisibilityChange);
    frameId = web.window.requestAnimationFrame(
      ((num _) => finish(_copyIntoFrameSnapshot(canvas, logicalSize))).toJS,
    );
    return completer.future;
  }

  /// Synchronous by contract. Anything awaited here would forfeit the frame.
  ///
  /// Copies at the largest size any capture can ask for rather than the
  /// canvas's device-pixel size. A 2x display backs a 1188x777 capture with a
  /// 2800x1831 canvas, so copying the whole surface would move ~4.6x the
  /// pixels a capture can use, inside the frame callback. Downscaling here
  /// also relieves `createImageBitmap` of the same resize later, so most of
  /// this cost is moved rather than added.
  bool _copyIntoFrameSnapshot(web.HTMLCanvasElement source, Size logicalSize) {
    // A frame callback queued before [dispose] still runs after it. Without
    // this, the copy below would allocate a replacement for the canvas
    // cleanup just released and leak it for the life of the page.
    if (_isDisposed) return false;
    if (source.width == 0 || source.height == 0) return false;
    final snapshotWatch = Stopwatch()..start();
    final wanted = _snapshotExtent(source, logicalSize);
    final width = wanted.$1;
    final height = wanted.$2;
    if (width == 0 || height == 0) return false;
    try {
      var target = _frameSnapshot;
      if (target == null || target.width != width || target.height != height) {
        target = web.document.createElement('canvas') as web.HTMLCanvasElement;
        target.width = width;
        target.height = height;
        _frameSnapshot = target;
      }
      final context = target.getContext('2d');
      if (context == null) return false;
      final canvas2d = context as web.CanvasRenderingContext2D;
      canvas2d.clearRect(0, 0, width.toDouble(), height.toDouble());
      canvas2d.drawImage(
        source,
        0,
        0,
        source.width.toDouble(),
        source.height.toDouble(),
        0,
        0,
        width.toDouble(),
        height.toDouble(),
      );
      _frameSnapshotIsFresh = true;
      _frameSnapshotFrame = _framesPainted;
      _lastFrameSnapshot = snapshotWatch.elapsed;
      if (_lastFrameSnapshot > _slowSnapshotThreshold) {
        // Inside the frame callback, so this directly delays presentation.
        _logger.warning(
          'In-frame surface snapshot took '
          '${_lastFrameSnapshot.inMilliseconds}ms for ${width}x$height; '
          'frame delivery may suffer on this device',
        );
      }
      return true;
    } catch (error) {
      _reportSkip('Web surface snapshot failed: $error');
      return false;
    }
  }

  /// Above this, the copy is a plausible cause of a dropped frame rather than
  /// noise, so it is worth a line in the log on slow devices.
  static const _slowSnapshotThreshold = Duration(milliseconds: 8);

  /// The largest extent a capture can request, never upscaling past the
  /// surface actually rendered.
  (int, int) _snapshotExtent(web.HTMLCanvasElement source, Size wanted) {
    final width = wanted.width.ceil();
    final height = wanted.height.ceil();
    if (width <= 0 || height <= 0) return (source.width, source.height);
    return (
      width < source.width ? width : source.width,
      height < source.height ? height : source.height,
    );
  }

  static Future<bool> _nextAnimationFrame() {
    if (web.document.hidden) return Future.value(false);
    final completer = Completer<bool>();
    late final int frameId;
    late final JSFunction onVisibilityChange;
    void finish(bool presented) {
      if (completer.isCompleted) return;
      web.window.cancelAnimationFrame(frameId);
      web.document.removeEventListener('visibilitychange', onVisibilityChange);
      completer.complete(presented);
    }

    onVisibilityChange = ((web.Event _) {
      if (web.document.hidden) finish(false);
    }).toJS;
    web.document.addEventListener('visibilitychange', onVisibilityChange);
    frameId = web.window.requestAnimationFrame(((num _) => finish(true)).toJS);
    return completer.future;
  }

  @override
  Future<void> waitForRenderedSurfacePresentation() async {
    // WebGL preparation already waited for its rendering frame. Crossing
    // another browser frame here would read a cleared buffer on static screens.
    if (!_requiresSameFrameSnapshot) await _nextAnimationFrame();
  }

  @override
  Future<CapturedSurface?> capture({
    required Size logicalSize,
    required int outputWidth,
    required int outputHeight,
  }) async {
    if (!isAvailable || web.document.hidden) return null;

    final captureWatch = Stopwatch()..start();
    final lookup = _SurfaceLookup.of(logicalSize);
    final surfaceLookup = captureWatch.elapsed;
    if (!lookup.isReady) {
      _reportSkip(lookup.describeSkip(logicalSize));
      return null;
    }
    final matchingCanvases = lookup.matches;

    // On WebGL surfaces the live canvas has already been cleared by now, so
    // the bitmap is built from the copy taken inside the frame callback.
    final web.HTMLCanvasElement bitmapSource;
    if (_requiresSameFrameSnapshot) {
      final snapshot = _frameSnapshot;
      if (snapshot == null || !_frameSnapshotIsFresh) {
        _reportSkip(
          'No in-frame surface snapshot for this capture; dropping the frame',
        );
        return null;
      }
      // Masks were read after this point and may describe a later frame.
      if (_frameSnapshotFrame != _framesPainted) {
        _frameSnapshotIsFresh = false;
        _reportSkip(
          'Flutter advanced past the copied frame before masks were read; '
          'dropping the frame rather than masking stale pixels',
        );
        return null;
      }
      bitmapSource = snapshot;
      // One capture per snapshot: a later attempt must take its own frame
      // rather than re-encode stale pixels.
      _frameSnapshotIsFresh = false;
    } else {
      bitmapSource = matchingCanvases.single;
    }

    web.ImageBitmap? imageBitmap;
    try {
      imageBitmap = await web.window
          .createImageBitmap(
            bitmapSource,
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
      if (!await _nextAnimationFrame()) return null;
      if (!isAvailable) return null;
      final snapshot = _WebCapturedSurface(
        imageBitmap,
        _encoder,
        outputWidth,
        outputHeight,
        (workerProcessing) {
          lastCaptureTimings = WebImageCaptureTimings(
            frameSnapshot: _lastFrameSnapshot,
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

  static web.ShadowRoot? _shadowRoot(web.Element? host) => host?.shadowRoot;

  @override
  Future<void> dispose() {
    _isDisposed = true;
    // Drop the backing bitmap; a stale one would otherwise outlive the SDK.
    _frameSnapshot?.width = 0;
    _frameSnapshot?.height = 0;
    _frameSnapshot = null;
    _frameSnapshotIsFresh = false;
    _frameSnapshotFrame = null;
    return _encoder.dispose();
  }
}

/// One inspection of the DOM for Flutter's rendering surface.
class _SurfaceLookup {
  const _SurfaceLookup._({
    required this.canvases,
    required this.matches,
    required this.hasMultipleViews,
    required this.hasNoVisibleCanvas,
  });

  factory _SurfaceLookup.of(Size logicalSize) {
    const tolerance = 2.0;
    final (canvases, hasMultipleViews) = _flutterCanvases();
    var hasNoVisibleCanvas = true;
    final matches = canvases
        .where((canvas) {
          final bounds = canvas.getBoundingClientRect();
          if (bounds.width > 0 && bounds.height > 0) {
            hasNoVisibleCanvas = false;
          }
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
      hasNoVisibleCanvas: hasNoVisibleCanvas,
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

  /// No Flutter canvas has presented yet. skwasm may mount a zero-sized canvas
  /// before its first raster completes; that is cold startup, not a resize.
  final bool hasNoVisibleCanvas;

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
        // The engine appends every flt-platform-view to the glass pane's
        // light DOM, so an HtmlElementView holding a viewport-sized canvas
        // (a map, a game, a document viewer) would otherwise be mistaken for
        // Flutter's own surface. closest() stops at the shadow boundary, so
        // a canvas the engine owns is never rejected here.
        if (canvas != null &&
            canvas.closest('flt-platform-view') == null &&
            !canvases.contains(canvas)) {
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
    this.frameSnapshot = Duration.zero,
    required this.surfaceLookup,
    required this.bitmapCreation,
    required this.snapshotValidation,
    required this.workerProcessing,
  });

  /// Zero unless the surface needed an in-frame copy (WebGL canvases).
  final Duration frameSnapshot;
  final Duration surfaceLookup;
  final Duration bitmapCreation;
  final Duration snapshotValidation;
  final Duration workerProcessing;

  Map<String, int> toMillisecondsJson() => {
    'frame_snapshot_ms': frameSnapshot.inMilliseconds,
    'surface_lookup_ms': surfaceLookup.inMilliseconds,
    'bitmap_creation_ms': bitmapCreation.inMilliseconds,
    'snapshot_validation_window_ms': snapshotValidation.inMilliseconds,
    'worker_processing_ms': workerProcessing.inMilliseconds,
  };
}

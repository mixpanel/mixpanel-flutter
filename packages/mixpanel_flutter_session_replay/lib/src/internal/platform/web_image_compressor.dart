import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:web/web.dart' as web;

import 'web_image_worker.dart';
import '../screenshot_capturer.dart';
import '../logger.dart';
import '../../models/configuration.dart';

/// Web image compressor using browser-native JPEG encoding.
///
/// Delegates to a Web Worker that uses OffscreenCanvas.convertToBlob()
/// for hardware-accelerated JPEG compression off the main thread.
class WebImageCompressor extends ImageCompressor {
  static const _workerTimeout = Duration(seconds: 5);
  static const _engineSurfaceHostSelector =
      'flutter-view, flt-glass-pane, flt-scene-host, flt-renderer';

  final MixpanelLogger _logger;
  final double jpegQuality;
  final WebPlatformViewCapturePolicy platformViewCapturePolicy;

  WebImageWorker? _worker;
  bool _workerUnavailable = false;

  /// Timings from the most recent rendered-surface capture. Intended for
  /// integration benchmarks; these durations do not affect capture behavior.
  WebImageCaptureTimings? lastCaptureTimings;

  WebImageCompressor({
    required MixpanelLogger logger,
    this.jpegQuality = 0.8,
    this.platformViewCapturePolicy =
        WebPlatformViewCapturePolicy.maskEntireFrame,
  }) : _logger = logger;

  @override
  bool get isAvailable => !_workerUnavailable;

  @override
  bool get paintsMasks => true;

  @override
  bool get capturesRenderedSurface => true;

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

  /// Verify both worker creation and its OffscreenCanvas JPEG path before the
  /// recorder is exposed to the host application. Web replay fails closed when
  /// this cannot complete; encoding RGBA on the main isolate causes visible
  /// multi-second stalls at desktop viewport sizes.
  Future<void> initialize() async {
    try {
      _worker ??= _initWorker();
      final canvas = web.HTMLCanvasElement()
        ..width = 1
        ..height = 1;
      final imageBitmap = await web.window.createImageBitmap(canvas).toDart;
      await _worker!
          .processImageBitmap(
            imageBitmap: imageBitmap,
            width: 1,
            height: 1,
            jpegQuality: jpegQuality,
            maskRects: const [],
          )
          .timeout(_workerTimeout);
    } catch (error) {
      _workerUnavailable = true;
      _worker?.dispose();
      _worker = null;
      throw UnsupportedError(
        'Web Worker JPEG encoding is required for Session Replay: $error',
      );
    }
  }

  @override
  Future<Uint8List?> captureRenderedSurface({
    required Size logicalSize,
    required int outputWidth,
    required int outputHeight,
    List<Rect> maskRects = const [],
    bool Function()? validateSnapshot,
  }) async {
    if (_workerUnavailable) return null;

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

    try {
      final imageBitmap = await web.window
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
      final snapshotValidationStart = captureWatch.elapsed;
      if (validateSnapshot != null) {
        // The ImageBitmap is already immutable, so it is safe to give the
        // browser a paint opportunity before walking the Flutter tree again.
        // This keeps the pre-snapshot and post-snapshot privacy traversals out
        // of the same rendered frame on slower devices. Nothing leaves the
        // main thread until validation succeeds.
        await _nextAnimationFrame();
        if (!validateSnapshot()) {
          imageBitmap.close();
          return null;
        }
      }
      final snapshotValidation = captureWatch.elapsed - snapshotValidationStart;
      _worker ??= _initWorker();
      final effectiveMaskRects =
          _hasPlatformViews() &&
              platformViewCapturePolicy ==
                  WebPlatformViewCapturePolicy.maskEntireFrame
          ? [
              Rect.fromLTWH(
                0,
                0,
                outputWidth.toDouble(),
                outputHeight.toDouble(),
              ),
            ]
          : maskRects;
      final workerStart = captureWatch.elapsed;
      final result = await _worker!
          .processImageBitmap(
            imageBitmap: imageBitmap,
            width: outputWidth,
            height: outputHeight,
            jpegQuality: jpegQuality,
            maskRects: effectiveMaskRects,
          )
          .timeout(_workerTimeout);
      lastCaptureTimings = WebImageCaptureTimings(
        surfaceLookup: surfaceLookup,
        bitmapCreation: bitmapCreation,
        snapshotValidation: snapshotValidation,
        workerProcessing: captureWatch.elapsed - workerStart,
      );
      return result;
    } catch (error) {
      _logger.warning(
        'Web surface capture or JPEG encoding failed; dropping this frame and '
        'restarting the worker on the next capture: $error',
      );
      _worker?.dispose();
      _worker = null;
      return null;
    }
  }

  @override
  Future<Uint8List?> compress(
    Uint8List rgbaBytes, {
    required int width,
    required int height,
    List<Rect> maskRects = const [],
  }) async {
    if (_workerUnavailable) return null;
    try {
      _worker ??= _initWorker();
      return await _worker!
          .processImage(
            rgbaBytes: rgbaBytes,
            width: width,
            height: height,
            jpegQuality: jpegQuality,
            maskRects: maskRects,
          )
          .timeout(_workerTimeout);
    } catch (error) {
      _logger.warning(
        'Web Worker JPEG encoding failed; dropping this frame and restarting '
        'the worker on the next capture: $error',
      );
      _worker?.dispose();
      _worker = null;
      return null;
    }
  }

  WebImageWorker _initWorker() {
    final worker = WebImageWorker.create();
    if (worker == null) {
      throw StateError(
        'Failed to create Web Worker. '
        'Check that your Content-Security-Policy allows blob: URLs for workers.',
      );
    }
    _logger.debug('Web Worker initialized for image processing');
    return worker;
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

  static bool _hasPlatformViews() {
    if (_querySelectorCount(web.document, 'flt-platform-view') > 0) {
      return true;
    }
    final hosts = web.document.querySelectorAll(_engineSurfaceHostSelector);
    for (var index = 0; index < hosts.length; index++) {
      final host = hosts.item(index) as web.Element?;
      final shadowRoot = _shadowRoot(host);
      if (shadowRoot != null &&
          _querySelectorCount(shadowRoot, 'flt-platform-view') > 0) {
        return true;
      }
    }
    return false;
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

  static int _querySelectorCount(JSObject root, String selector) => root
      .callMethod<JSObject>('querySelectorAll'.toJS, selector.toJS)
      .getProperty<JSNumber>('length'.toJS)
      .toDartInt;

  @override
  Future<void> dispose() async {
    _worker?.dispose();
    _worker = null;
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

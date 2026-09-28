import 'dart:async';
import 'dart:typed_data';
import 'dart:js_interop';
import 'dart:ui' show Rect;
import 'package:web/web.dart' as web;
import '../capture/image_compressor.dart';
import '../logger.dart';
import 'web_image_worker.dart';

/// Worker-backed JPEG encoding. Surface discovery and acquisition belong to
/// WebRenderedSurfaceCapture; this encoder owns only worker resources.
class WebImageCompressor extends ImageCompressor {
  static const _workerTimeout = Duration(seconds: 5);
  final MixpanelLogger _logger;
  final double jpegQuality;
  WebImageWorker? _worker;
  bool _workerUnavailable = false;
  bool _disposed = false;

  WebImageCompressor({required MixpanelLogger logger, this.jpegQuality = 0.8})
    : _logger = logger;

  @override
  bool get isAvailable => !_disposed && !_workerUnavailable;
  @override
  bool get paintsMasks => true;

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

  /// Takes ownership of [imageBitmap], including on encoding failure.
  Future<Uint8List?> compressBitmap({
    required web.ImageBitmap imageBitmap,
    required int width,
    required int height,
    required List<Rect> maskRects,
  }) async {
    if (!isAvailable) {
      imageBitmap.close();
      return null;
    }
    var transferred = false;
    try {
      _worker ??= _initWorker();
      final work = _worker!.processImageBitmap(
        imageBitmap: imageBitmap,
        width: width,
        height: height,
        jpegQuality: jpegQuality,
        maskRects: maskRects,
      );
      transferred = true;
      return await work.timeout(_workerTimeout);
    } catch (error) {
      if (!transferred) imageBitmap.close();
      _logger.warning('Web JPEG encoding failed; restarting worker: $error');
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
    if (!isAvailable) return null;
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

  @override
  Future<void> dispose() async {
    _disposed = true;
    _worker?.dispose();
    _worker = null;
  }
}

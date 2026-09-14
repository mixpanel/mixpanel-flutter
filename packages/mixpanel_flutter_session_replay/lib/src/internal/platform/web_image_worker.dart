import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/rendering.dart';

import 'package:web/web.dart' as web;

/// Inline JavaScript source for the image processing Web Worker.
///
/// Receives RGBA pixel data, draws it onto an OffscreenCanvas,
/// encodes to JPEG via convertToBlob, and transfers the result
/// back as an ArrayBuffer (zero-copy).
const String _workerScript = '''
self.onmessage = async function(e) {
  try {
    const {
      rgbaBuffer, imageBitmap, width, height, jpegQuality, maskRects
    } = e.data;
    const canvas = new OffscreenCanvas(width, height);
    const ctx = canvas.getContext('2d');
    if (imageBitmap) {
      ctx.drawImage(imageBitmap, 0, 0, width, height);
      imageBitmap.close();
    } else {
      const imageData = new ImageData(
        new Uint8ClampedArray(rgbaBuffer), width, height
      );
      ctx.putImageData(imageData, 0, 0);
    }

    ctx.fillStyle = '#cccccc';
    for (let i = 0; i < maskRects.length; i += 4) {
      ctx.fillRect(
        maskRects[i], maskRects[i + 1], maskRects[i + 2], maskRects[i + 3]
      );
    }

    const blob = await canvas.convertToBlob({
      type: 'image/jpeg',
      quality: jpegQuality
    });
    const jpegBuffer = await blob.arrayBuffer();
    self.postMessage({ jpegBuffer: jpegBuffer }, [jpegBuffer]);
  } catch (err) {
    self.postMessage({ error: err.message || String(err) });
  }
};
''';

/// Extension type for the worker's response message data.
extension type _WorkerResponse._(JSObject _) implements JSObject {
  external JSArrayBuffer? get jpegBuffer;
  external JSString? get error;
}

/// Extension type for the message payload sent to the worker.
extension type _WorkerMessage._(JSObject _) implements JSObject {
  external factory _WorkerMessage({
    JSArrayBuffer rgbaBuffer,
    JSNumber width,
    JSNumber height,
    JSNumber jpegQuality,
    JSArray<JSNumber> maskRects,
  });
}

/// Message payload for a GPU/browser-backed surface snapshot.
extension type _WorkerBitmapMessage._(JSObject _) implements JSObject {
  external factory _WorkerBitmapMessage({
    web.ImageBitmap imageBitmap,
    JSNumber width,
    JSNumber height,
    JSNumber jpegQuality,
    JSArray<JSNumber> maskRects,
  });
}

/// Manages a Web Worker for off-main-thread image compression.
///
/// Created once and reused for all captures. The worker paints privacy masks
/// and compresses RGBA pixels using browser-native OffscreenCanvas and
/// convertToBlob APIs.
class WebImageWorker {
  final web.Worker _worker;
  final String _blobUrl;
  Completer<Uint8List>? _pending;
  bool _disposed = false;

  WebImageWorker._(this._worker, this._blobUrl) {
    _worker.onmessage = _onMessage.toJS;
    _worker.onerror = _onError.toJS;
  }

  /// Creates a new Web Worker from an inline Blob URL.
  ///
  /// Returns `null` if worker creation fails (e.g., CSP blocks Blob URLs).
  static WebImageWorker? create() {
    try {
      final blob = web.Blob(
        [_workerScript.toJS].toJS,
        web.BlobPropertyBag(type: 'text/javascript'),
      );
      final blobUrl = web.URL.createObjectURL(blob);
      final worker = web.Worker(blobUrl.toJS);
      return WebImageWorker._(worker, blobUrl);
    } catch (_) {
      return null;
    }
  }

  /// Compresses raw RGBA pixel data into a JPEG image.
  ///
  /// The [rgbaBytes] ArrayBuffer is transferred to the worker (zero-copy)
  /// and cannot be used after this call. The JPEG result is transferred
  /// back (also zero-copy).
  Future<Uint8List> processImage({
    required Uint8List rgbaBytes,
    required int width,
    required int height,
    required double jpegQuality,
    required List<Rect> maskRects,
  }) {
    if (_disposed) {
      return Future.error(StateError('WebImageWorker is disposed'));
    }
    if (_pending != null) {
      return Future.error(StateError('Worker is already processing an image'));
    }

    // Construct the complete message before recording an in-flight request.
    // A synchronous interop error must not leave [_pending] stranded and then
    // get obscured by the error raised when the compressor disposes the worker.
    final rgbaArrayBuffer = rgbaBytes.buffer.toJS;
    final jsMaskRects = _maskRectsToJs(maskRects);
    final message = _WorkerMessage(
      rgbaBuffer: rgbaArrayBuffer,
      width: width.toJS,
      height: height.toJS,
      jpegQuality: jpegQuality.toJS,
      maskRects: jsMaskRects,
    );

    final completer = Completer<Uint8List>();
    _pending = completer;
    try {
      _worker.postMessage(message, [rgbaArrayBuffer].toJS);
    } catch (error, stackTrace) {
      _pending = null;
      completer.completeError(error, stackTrace);
    }

    return completer.future;
  }

  /// Scales, masks, and encodes a transferable browser surface snapshot.
  ///
  /// Ownership of [imageBitmap] is transferred to the worker. This avoids a
  /// synchronous GPU readback and avoids copying RGBA through Dart/Wasm.
  Future<Uint8List> processImageBitmap({
    required web.ImageBitmap imageBitmap,
    required int width,
    required int height,
    required double jpegQuality,
    required List<Rect> maskRects,
  }) {
    if (_disposed) {
      imageBitmap.close();
      return Future.error(StateError('WebImageWorker is disposed'));
    }
    if (_pending != null) {
      imageBitmap.close();
      return Future.error(StateError('Worker is already processing an image'));
    }

    final jsMaskRects = _maskRectsToJs(maskRects);
    final message = _WorkerBitmapMessage(
      imageBitmap: imageBitmap,
      width: width.toJS,
      height: height.toJS,
      jpegQuality: jpegQuality.toJS,
      maskRects: jsMaskRects,
    );
    final completer = Completer<Uint8List>();
    _pending = completer;
    try {
      _worker.postMessage(message, [imageBitmap].toJS);
    } catch (error, stackTrace) {
      _pending = null;
      imageBitmap.close();
      completer.completeError(error, stackTrace);
    }
    return completer.future;
  }

  static JSArray<JSNumber> _maskRectsToJs(List<Rect> maskRects) => <JSNumber>[
    for (final rect in maskRects) ...<JSNumber>[
      rect.left.toJS,
      rect.top.toJS,
      rect.width.toJS,
      rect.height.toJS,
    ],
  ].toJS;

  void _onMessage(web.MessageEvent event) {
    final completer = _pending;
    if (completer == null) return;
    _pending = null;

    final response = event.data as _WorkerResponse;

    final error = response.error;
    if (error != null) {
      completer.completeError(Exception('Worker error: ${error.toDart}'));
      return;
    }

    final jpegBuffer = response.jpegBuffer;
    if (jpegBuffer == null) {
      completer.completeError(Exception('Worker returned no data'));
      return;
    }

    completer.complete(jpegBuffer.toDart.asUint8List());
  }

  void _onError(web.Event event) {
    final completer = _pending;
    if (completer == null) return;
    _pending = null;
    completer.completeError(Exception('Worker execution error'));
  }

  /// Terminates the worker and revokes the Blob URL.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _worker.terminate();
    web.URL.revokeObjectURL(_blobUrl);

    final completer = _pending;
    if (completer != null) {
      _pending = null;
      completer.completeError(StateError('Worker disposed during processing'));
    }
  }
}

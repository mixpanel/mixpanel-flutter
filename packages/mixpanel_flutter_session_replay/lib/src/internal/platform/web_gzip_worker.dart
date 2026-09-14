import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

const String _workerScript = '''
self.onmessage = async function(e) {
  try {
    const inputBuffer = e.data.inputBuffer;
    const input = new Blob([inputBuffer]);
    const compressedStream = input.stream().pipeThrough(
      new CompressionStream('gzip')
    );
    const outputBuffer = await new Response(compressedStream).arrayBuffer();
    self.postMessage({ outputBuffer: outputBuffer }, [outputBuffer]);
  } catch (err) {
    self.postMessage({ error: err.message || String(err) });
  }
};
''';

extension type _WorkerResponse._(JSObject _) implements JSObject {
  external JSArrayBuffer? get outputBuffer;
  external JSString? get error;
}

extension type _WorkerMessage._(JSObject _) implements JSObject {
  external factory _WorkerMessage({JSArrayBuffer inputBuffer});
}

/// Reusable worker that performs the entire browser gzip pipeline off the
/// Flutter UI isolate.
class WebGzipWorker {
  final web.Worker _worker;
  final String _blobUrl;
  Completer<Uint8List>? _pending;
  Future<void> _tail = Future<void>.value();
  bool _disposed = false;

  WebGzipWorker._(this._worker, this._blobUrl) {
    _worker.onmessage = _onMessage.toJS;
    _worker.onerror = _onError.toJS;
  }

  static WebGzipWorker? create() {
    try {
      final blob = web.Blob(
        [_workerScript.toJS].toJS,
        web.BlobPropertyBag(type: 'text/javascript'),
      );
      final blobUrl = web.URL.createObjectURL(blob);
      final worker = web.Worker(blobUrl.toJS);
      return WebGzipWorker._(worker, blobUrl);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> compress(Uint8List bytes) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;

    await previous;
    if (_disposed) {
      done.complete();
      throw StateError('WebGzipWorker is disposed');
    }

    try {
      final completer = Completer<Uint8List>();
      _pending = completer;
      final inputBuffer = bytes.buffer.toJS;
      _worker.postMessage(
        _WorkerMessage(inputBuffer: inputBuffer),
        [inputBuffer].toJS,
      );
      return await completer.future;
    } finally {
      done.complete();
    }
  }

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

    final outputBuffer = response.outputBuffer;
    if (outputBuffer == null) {
      completer.completeError(Exception('Worker returned no data'));
      return;
    }
    completer.complete(outputBuffer.toDart.asUint8List());
  }

  void _onError(web.Event event) {
    final completer = _pending;
    if (completer == null) return;
    _pending = null;
    completer.completeError(Exception('Worker execution error'));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _worker.terminate();
    web.URL.revokeObjectURL(_blobUrl);

    final completer = _pending;
    if (completer != null) {
      _pending = null;
      completer.completeError(StateError('Worker disposed during compression'));
    }
  }
}

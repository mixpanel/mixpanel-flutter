import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'web_gzip_worker.dart';

const _workerTimeout = Duration(seconds: 5);
WebGzipWorker? _worker;
bool _workerUnavailable = false;
bool _workerInitialized = false;
Future<void>? _initializing;

bool get isGzipSupported {
  try {
    web.CompressionStream('gzip');
    return true;
  } catch (_) {
    return false;
  }
}

List<int> gzipCompress(List<int> bytes) {
  throw UnsupportedError('Use gzipCompressAsync on web');
}

/// Verify that a worker can execute the browser's CompressionStream pipeline.
Future<void> initializeGzipCompression() {
  if (_workerInitialized) return Future<void>.value();
  if (_workerUnavailable) {
    return Future<void>.error(
      UnsupportedError('Web Worker gzip compression is unavailable'),
    );
  }
  return _initializing ??= _initializeGzipCompression();
}

Future<void> _initializeGzipCompression() async {
  WebGzipWorker? worker;
  try {
    worker = _worker ??= WebGzipWorker.create();
    if (worker == null) throw UnsupportedError('Web Worker creation failed');
    await worker.compress(Uint8List(0)).timeout(_workerTimeout);
    if (identical(_worker, worker)) _workerInitialized = true;
  } catch (error) {
    // Only judge the worker this attempt used. If dispose() replaced it
    // meanwhile, a failure here says nothing about the replacement.
    if (worker == null || identical(_worker, worker)) {
      _workerUnavailable = true;
      _worker = null;
    }
    worker?.dispose();
    throw UnsupportedError(
      'Web Worker gzip compression is required for Session Replay: $error',
    );
  } finally {
    _initializing = null;
  }
}

/// Terminate the shared worker and release its Blob URL.
///
/// Called when the SDK instance is disposed. The worker is recreated lazily
/// by the next upload, so a later re-initialization keeps working.
void disposeGzipCompression() {
  _worker?.dispose();
  _worker = null;
  _workerInitialized = false;
  _workerUnavailable = false;
}

/// Gzip compress using CompressionStream inside a dedicated Web Worker.
Future<List<int>> gzipCompressAsync(List<int> bytes) async {
  if (_workerUnavailable) {
    throw UnsupportedError('Web Worker gzip compression is unavailable');
  }
  WebGzipWorker? worker;
  try {
    worker = _worker ??= WebGzipWorker.create();
    if (worker == null) throw UnsupportedError('Web Worker creation failed');
    return await worker
        .compress(Uint8List.fromList(bytes))
        .timeout(_workerTimeout);
  } catch (error) {
    // A request that started on a since-disposed worker must not tear down
    // the worker that replaced it.
    if (identical(_worker, worker)) {
      _workerInitialized = false;
      _worker = null;
    }
    worker?.dispose();
    throw UnsupportedError(
      'Web Worker gzip compression failed; the worker will restart on the '
      'next upload attempt: $error',
    );
  }
}

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
  try {
    _worker ??= WebGzipWorker.create();
    final worker = _worker;
    if (worker == null) throw UnsupportedError('Web Worker creation failed');
    await worker.compress(Uint8List(0)).timeout(_workerTimeout);
    _workerInitialized = true;
  } catch (error) {
    _workerUnavailable = true;
    _worker?.dispose();
    _worker = null;
    throw UnsupportedError(
      'Web Worker gzip compression is required for Session Replay: $error',
    );
  } finally {
    _initializing = null;
  }
}

/// Gzip compress using CompressionStream inside a dedicated Web Worker.
Future<List<int>> gzipCompressAsync(List<int> bytes) async {
  if (_workerUnavailable) {
    throw UnsupportedError('Web Worker gzip compression is unavailable');
  }
  try {
    _worker ??= WebGzipWorker.create();
    final worker = _worker;
    if (worker == null) throw UnsupportedError('Web Worker creation failed');
    return await worker
        .compress(Uint8List.fromList(bytes))
        .timeout(_workerTimeout);
  } catch (error) {
    _workerInitialized = false;
    _worker?.dispose();
    _worker = null;
    throw UnsupportedError(
      'Web Worker gzip compression failed; the worker will restart on the '
      'next upload attempt: $error',
    );
  }
}

import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'gzip_compressor_types.dart';
import 'web_gzip_worker.dart';

export 'gzip_compressor_types.dart';

GzipCompressor createGzipCompressor() => WebGzipCompressor();

/// Gzip via CompressionStream inside a dedicated Web Worker.
///
/// The worker is created lazily, recreated after a failure, and terminated by
/// [dispose]. Because each SDK instance owns its own compressor, a request
/// still in flight when one instance is disposed can only ever fail against
/// that instance's worker.
class WebGzipCompressor implements GzipCompressor {
  static const _workerTimeout = Duration(seconds: 5);

  WebGzipWorker? _worker;
  bool _unavailable = false;
  bool _initialized = false;
  bool _disposed = false;
  Future<void>? _initializing;

  @override
  bool get isSupported {
    try {
      web.CompressionStream('gzip');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Verify that a worker can execute the browser's CompressionStream pipeline.
  @override
  Future<void> initialize() {
    _checkNotDisposed();
    if (_initialized) return Future<void>.value();
    if (_unavailable) {
      return Future<void>.error(
        UnsupportedError('Web Worker gzip compression is unavailable'),
      );
    }
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    WebGzipWorker? worker;
    try {
      worker = _worker ??= WebGzipWorker.create();
      if (worker == null) throw UnsupportedError('Web Worker creation failed');
      await worker.compress(Uint8List(0), timeout: _workerTimeout);
      if (identical(_worker, worker)) _initialized = true;
    } catch (error) {
      // Judge only the worker this attempt used; a restart may have replaced it.
      if (worker == null || identical(_worker, worker)) {
        _unavailable = true;
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

  @override
  Future<List<int>> compress(List<int> bytes) async {
    _checkNotDisposed();
    if (_unavailable) {
      throw UnsupportedError('Web Worker gzip compression is unavailable');
    }
    WebGzipWorker? worker;
    try {
      worker = _worker ??= WebGzipWorker.create();
      if (worker == null) throw UnsupportedError('Web Worker creation failed');
      return await worker.compress(
        Uint8List.fromList(bytes),
        timeout: _workerTimeout,
      );
    } catch (error) {
      // A request that started on a worker this instance has since replaced
      // must not tear down the replacement.
      if (identical(_worker, worker)) {
        _initialized = false;
        _worker = null;
      }
      worker?.dispose();
      throw UnsupportedError(
        'Web Worker gzip compression failed; the worker will restart on the '
        'next upload attempt: $error',
      );
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _worker?.dispose();
    _worker = null;
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('WebGzipCompressor has been disposed');
  }
}

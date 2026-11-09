import 'dart:io' show gzip;

import 'gzip_compressor_types.dart';

export 'gzip_compressor_types.dart';

GzipCompressor createGzipCompressor() => const IoGzipCompressor();

/// dart:io gzip; stateless, so there is nothing to initialize or release.
class IoGzipCompressor implements GzipCompressor {
  const IoGzipCompressor();

  @override
  bool get isSupported => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<int>> compress(List<int> bytes) async => gzip.encode(bytes);

  @override
  void dispose() {}
}

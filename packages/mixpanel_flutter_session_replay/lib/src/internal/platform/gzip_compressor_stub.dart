import 'gzip_compressor_types.dart';

export 'gzip_compressor_types.dart';

GzipCompressor createGzipCompressor() => const UnsupportedGzipCompressor();

/// Placeholder for platforms with neither dart:io nor JS interop.
class UnsupportedGzipCompressor implements GzipCompressor {
  const UnsupportedGzipCompressor();

  @override
  bool get isSupported => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<int>> compress(List<int> bytes) async => bytes;

  @override
  void dispose() {}
}

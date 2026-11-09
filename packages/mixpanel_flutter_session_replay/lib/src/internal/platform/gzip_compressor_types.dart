/// Gzip compression for upload payloads.
///
/// One instance belongs to one SDK instance, so disposing an SDK instance can
/// never affect a compression another instance has in flight.
abstract class GzipCompressor {
  /// Whether this platform can gzip at all.
  bool get isSupported;

  /// Verifies the compressor works end to end. Throws when it cannot.
  Future<void> initialize();

  /// Gzip-compresses [bytes].
  Future<List<int>> compress(List<int> bytes);

  /// Releases any platform resources. Further calls fail.
  void dispose();
}

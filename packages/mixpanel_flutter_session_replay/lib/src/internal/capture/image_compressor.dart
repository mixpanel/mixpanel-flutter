import 'dart:typed_data';

/// Interface for platform-specific image compression.
///
/// Implementations compress raw RGBA bytes, already masked, into an encoded
/// format (typically JPEG). Used by `ToImageFrameAcquirer`; native
/// implementations call the Android/iOS JPEG encoders over a MethodChannel.
abstract class ImageCompressor {
  /// Whether this compressor can still accept work.
  ///
  /// Platform implementations can switch this to false after a permanent
  /// runtime failure so frame capture stops before allocating an RGBA image.
  bool get isAvailable => true;

  /// Compress raw RGBA bytes into an encoded image.
  ///
  /// Returns compressed bytes, or null on failure.
  Future<Uint8List?> compress(
    Uint8List rgbaBytes, {
    required int width,
    required int height,
  });

  /// Release resources held by the compressor.
  Future<void> dispose();
}

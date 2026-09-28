import 'dart:typed_data';
import 'dart:ui' show Rect;

/// Interface for platform-specific image compression.
///
/// Implementations handle compressing raw RGBA bytes into an encoded
/// format (typically JPEG) using platform-optimized APIs:
/// - Native: MethodChannel to Android/iOS JPEG encoders
/// - Web: OffscreenCanvas.convertToBlob() via Web Worker
abstract class ImageCompressor {
  /// Whether this compressor can still accept work.
  ///
  /// Platform implementations can switch this to false after a permanent
  /// runtime failure so frame capture stops before allocating an RGBA image.
  bool get isAvailable => true;

  /// Whether privacy mask rectangles are painted by the compressor.
  ///
  /// Web performs this inside its image worker to avoid rendering a second
  /// full-size Flutter image on the UI isolate. Native compressors keep the
  /// default and receive pixels already masked by the mask painter.
  bool get paintsMasks => false;

  /// Compress raw RGBA bytes into an encoded image.
  ///
  /// Returns compressed bytes, or null on failure.
  Future<Uint8List?> compress(
    Uint8List rgbaBytes, {
    required int width,
    required int height,
    List<Rect> maskRects = const [],
  });

  /// Release resources held by the compressor.
  Future<void> dispose();
}

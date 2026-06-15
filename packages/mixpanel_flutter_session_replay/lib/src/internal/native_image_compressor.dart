import 'package:flutter/services.dart';

/// Compresses RGBA image data to JPEG using platform-native encoders.
///
/// Uses MethodChannel to call Android's Bitmap.compress() (libjpeg-turbo)
/// or iOS/macOS's UIImage.jpegData / CGImageDestination for hardware-optimized encoding.
///
/// The MethodChannel call is async and non-blocking — native compression runs on
/// platform background threads (Android: ExecutorService, iOS/macOS: DispatchQueue).
class NativeImageCompressor {
  static const _channel = MethodChannel('com.mixpanel.flutter_session_replay');

  /// Compress RGBA bytes to JPEG using native platform encoder.
  ///
  /// Returns compressed JPEG bytes, or null if native compression fails.
  Future<Uint8List?> compressToJpeg(
    Uint8List rgbaBytes, {
    required int width,
    required int height,
    required int quality,
  }) async {
    try {
      return await _channel.invokeMethod<Uint8List>('compressImage', {
        'rgbaBytes': rgbaBytes,
        'width': width,
        'height': height,
        'quality': quality,
      });
    } catch (_) {
      return null;
    }
  }

  /// Release native cached resources (bitmaps, buffers).
  ///
  /// Call this when session replay stops to free memory.
  /// Resources are automatically recreated on the next compression call.
  Future<void> dispose() async {
    try {
      await _channel.invokeMethod<void>('disposeCache');
    } catch (_) {
      // Best-effort cleanup — ignore failures
    }
  }
}

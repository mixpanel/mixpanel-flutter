import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'screenshot_capturer.dart';

/// Native image compressor using platform JPEG encoders.
///
/// Uses MethodChannel to call Android's Bitmap.compress() (libjpeg-turbo)
/// or iOS/macOS's UIImage.jpegData for hardware-optimized encoding.
/// Falls back to pure Dart encoding via isolate if native fails.
class NativeImageCompressor extends ImageCompressor {
  static const _channel = MethodChannel('com.mixpanel.flutter_session_replay');

  /// JPEG quality (0-100).
  /// iOS: 40 to match native SDK (ImageSettings.jpegCompressionRate = 0.4)
  /// Android: 80 to match native SDK (Bitmap.compress quality = 80)
  int get _jpegQuality => defaultTargetPlatform == TargetPlatform.iOS ? 40 : 80;

  @override
  Future<Uint8List?> compress(
    Uint8List rgbaBytes, {
    required int width,
    required int height,
    List<Rect> maskRects = const [],
  }) => compressToJpeg(
    rgbaBytes,
    width: width,
    height: height,
    quality: _jpegQuality,
  );

  Future<Uint8List?> compressToJpeg(
    Uint8List rgbaBytes, {
    required int width,
    required int height,
    required int quality,
  }) async {
    try {
      final result = await _channel.invokeMethod<Uint8List>('compressImage', {
        'rgbaBytes': rgbaBytes,
        'width': width,
        'height': height,
        'quality': quality,
      });
      if (result != null) return result;
    } catch (_) {
      // Fall through to Dart fallback.
    }

    try {
      return await compute(_compressInIsolate, (
        rgbaBytes,
        width,
        height,
        quality,
      ));
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _compressInIsolate((Uint8List, int, int, int) args) {
    final (rgbaBytes, width, height, quality) = args;
    try {
      final image = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgbaBytes.buffer,
        order: img.ChannelOrder.rgba,
      );
      return Uint8List.fromList(img.encodeJpg(image, quality: quality));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _channel.invokeMethod<void>('disposeCache');
    } catch (_) {
      // Best-effort cleanup.
    }
  }
}

/// Pure Dart PNG compressor for deterministic golden tests.
///
/// Uses a background isolate for encoding and produces byte-for-byte
/// reproducible output across runs.
class DartPngCompressor extends ImageCompressor {
  @override
  Future<Uint8List?> compress(
    Uint8List rgbaBytes, {
    required int width,
    required int height,
    List<Rect> maskRects = const [],
  }) async {
    try {
      return await compute(_compressInIsolate, (rgbaBytes, width, height));
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _compressInIsolate((Uint8List, int, int) args) {
    final (rgbaBytes, width, height) = args;
    try {
      final image = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgbaBytes.buffer,
        order: img.ChannelOrder.rgba,
      );
      return Uint8List.fromList(img.encodePng(image));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dispose() async {}
}

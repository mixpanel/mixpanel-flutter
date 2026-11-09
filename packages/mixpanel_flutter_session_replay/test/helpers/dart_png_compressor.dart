import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:mixpanel_flutter_session_replay/src/internal/capture/image_compressor.dart';

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

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/native_image_compressor.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final compressor = NativeImageCompressor();

  /// Pumps the deterministic test scene widget.
  Future<void> pumpTestScene(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 50,
              height: 50,
              child: RepaintBoundary(
                key: _boundaryKey,
                child: CustomPaint(
                  size: const Size(50, 50),
                  painter: DeterministicTestScene(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Generates valid RGBA bytes for a solid color image.
  Uint8List generateRgba(
    int width,
    int height, {
    int r = 0,
    int g = 0,
    int b = 0,
  }) {
    final bytes = Uint8List(width * height * 4);
    for (var i = 0; i < bytes.length; i += 4) {
      bytes[i] = r;
      bytes[i + 1] = g;
      bytes[i + 2] = b;
      bytes[i + 3] = 255; // alpha
    }
    return bytes;
  }

  // Pump a minimal widget so the test framework is happy
  Future<void> pumpMinimal(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
  }

  testWidgets('compressed output matches platform reference', (tester) async {
    await pumpTestScene(tester);

    final (rgbaBytes, width, height) =
        await tester.runAsync(() => captureRgba()) ?? (Uint8List(0), 0, 0);

    final jpegBytes = await tester.runAsync(
      () => compressor.compressToJpeg(
        rgbaBytes,
        width: width,
        height: height,
        quality: 80,
      ),
    );
    expect(jpegBytes, isNotNull);

    // Try to load platform-specific golden reference from assets
    Uint8List? referenceBytes;
    final assetPath = 'assets/compression_golden/$platformName/reference.jpg';
    try {
      final data = await rootBundle.load(assetPath);
      referenceBytes = data.buffer.asUint8List();
    } catch (_) {
      // Reference not found — save current output for developer to commit
    }

    if (referenceBytes == null) {
      final b64 = base64Encode(jpegBytes!);
      fail(
        'Golden reference not found for platform "$platformName".\n'
        'Expected asset: $assetPath\n'
        'To create the reference, run:\n\n'
        'base64 -d <<\'GOLDEN\' > example/$assetPath\n'
        '$b64\n'
        'GOLDEN',
      );
    }

    // Decode both images to compare
    final testImage = img.decodeJpg(jpegBytes!)!;
    final refImage = img.decodeJpg(referenceBytes)!;

    // If dimensions differ, provide new reference and fail
    if (testImage.width != refImage.width ||
        testImage.height != refImage.height) {
      final b64 = base64Encode(jpegBytes);
      fail(
        'Golden reference dimensions differ: '
        'got ${testImage.width}x${testImage.height}, '
        'reference is ${refImage.width}x${refImage.height}.\n'
        'If this change is intentional, update the golden reference:\n\n'
        'base64 -d <<\'GOLDEN\' > example/$assetPath\n'
        '$b64\n'
        'GOLDEN',
      );
    }

    // Compare pixel values
    final mae = computeMeanAbsoluteError(jpegBytes, referenceBytes);

    debugPrint(
      'Compression golden MAE ($platformName): ${mae.toStringAsFixed(2)} / 255',
    );

    // Threshold: MAE < 10.0 per channel (~4% tolerance).
    // Different devices on the same platform may use different JPEG encoder
    // implementations, producing slightly different output for identical input.
    // A broken encoder would produce MAE in the 50+ range.
    if (mae >= 10.0) {
      final b64 = base64Encode(jpegBytes);
      fail(
        'Mean absolute error per channel is ${mae.toStringAsFixed(2)} '
        '(threshold: < 10.0).\n'
        'If this change is intentional, update the golden reference:\n\n'
        'base64 -d <<\'GOLDEN\' > example/$assetPath\n'
        '$b64\n'
        'GOLDEN',
      );
    }
  });

  testWidgets('returns null for mismatched byte array size', (tester) async {
    await pumpMinimal(tester);
    final edgeCompressor = NativeImageCompressor();

    // 10x10 image needs 400 bytes, provide only 100
    final wrongSize = Uint8List(100);
    final result = await tester.runAsync(
      () => edgeCompressor.compressToJpeg(
        wrongSize,
        width: 10,
        height: 10,
        quality: 80,
      ),
    );

    expect(result, isNull, reason: 'Mismatched size should fail gracefully');

    await tester.runAsync(() => edgeCompressor.dispose());
  });

  testWidgets('returns null for empty bytes with non-zero dimensions', (
    tester,
  ) async {
    await pumpMinimal(tester);
    final edgeCompressor = NativeImageCompressor();

    final empty = Uint8List(0);
    final result = await tester.runAsync(
      () => edgeCompressor.compressToJpeg(
        empty,
        width: 10,
        height: 10,
        quality: 80,
      ),
    );

    expect(result, isNull, reason: 'Empty bytes should fail gracefully');

    await tester.runAsync(() => edgeCompressor.dispose());
  });

  testWidgets('cache reuse across multiple compressions', (tester) async {
    await pumpMinimal(tester);
    final edgeCompressor = NativeImageCompressor();

    // Compress same dimensions multiple times to exercise cache reuse
    final rgba = generateRgba(50, 50, r: 200, g: 100, b: 50);
    for (var i = 0; i < 5; i++) {
      final result = await tester.runAsync(
        () => edgeCompressor.compressToJpeg(
          rgba,
          width: 50,
          height: 50,
          quality: 80,
        ),
      );
      expect(result, isNotNull, reason: 'Compression $i should succeed');
    }

    await tester.runAsync(() => edgeCompressor.dispose());
  });

  testWidgets('cache handles dimension changes', (tester) async {
    await pumpMinimal(tester);
    final edgeCompressor = NativeImageCompressor();

    // First compression at 50x50
    final rgba1 = generateRgba(50, 50, r: 255);
    final result1 = await tester.runAsync(
      () => edgeCompressor.compressToJpeg(
        rgba1,
        width: 50,
        height: 50,
        quality: 80,
      ),
    );
    expect(result1, isNotNull);

    // Second compression at 100x100 (different dimensions invalidate cache)
    final rgba2 = generateRgba(100, 100, g: 255);
    final result2 = await tester.runAsync(
      () => edgeCompressor.compressToJpeg(
        rgba2,
        width: 100,
        height: 100,
        quality: 80,
      ),
    );
    expect(result2, isNotNull);

    // Back to 50x50
    final result3 = await tester.runAsync(
      () => edgeCompressor.compressToJpeg(
        rgba1,
        width: 50,
        height: 50,
        quality: 80,
      ),
    );
    expect(result3, isNotNull);

    await tester.runAsync(() => edgeCompressor.dispose());
  });

  testWidgets('quality parameter affects output size', (tester) async {
    await pumpMinimal(tester);
    final edgeCompressor = NativeImageCompressor();

    // Use a non-trivial image (gradient-like) so quality matters
    final rgba = Uint8List(200 * 200 * 4);
    for (var y = 0; y < 200; y++) {
      for (var x = 0; x < 200; x++) {
        final i = (y * 200 + x) * 4;
        rgba[i] = x % 256;
        rgba[i + 1] = y % 256;
        rgba[i + 2] = (x + y) % 256;
        rgba[i + 3] = 255;
      }
    }

    final lowQuality = await tester.runAsync(
      () => edgeCompressor.compressToJpeg(
        rgba,
        width: 200,
        height: 200,
        quality: 10,
      ),
    );
    final highQuality = await tester.runAsync(
      () => edgeCompressor.compressToJpeg(
        rgba,
        width: 200,
        height: 200,
        quality: 95,
      ),
    );

    expect(lowQuality, isNotNull);
    expect(highQuality, isNotNull);
    expect(
      lowQuality!.length,
      lessThan(highQuality!.length),
      reason: 'Lower quality should produce smaller output',
    );

    await tester.runAsync(() => edgeCompressor.dispose());
  });

  testWidgets('dispose is idempotent', (tester) async {
    await pumpMinimal(tester);
    final edgeCompressor = NativeImageCompressor();

    // Compress first to populate cache
    final rgba = generateRgba(10, 10, r: 255);
    await tester.runAsync(
      () => edgeCompressor.compressToJpeg(
        rgba,
        width: 10,
        height: 10,
        quality: 80,
      ),
    );

    // Multiple dispose calls should not throw
    await tester.runAsync(() => edgeCompressor.dispose());
    await tester.runAsync(() => edgeCompressor.dispose());
    await tester.runAsync(() => edgeCompressor.dispose());
  });

  testWidgets('compression works after dispose and reuse', (tester) async {
    await pumpMinimal(tester);
    final edgeCompressor = NativeImageCompressor();

    final rgba = generateRgba(20, 20, b: 255);

    // Compress, dispose, then compress again
    final first = await tester.runAsync(
      () => edgeCompressor.compressToJpeg(
        rgba,
        width: 20,
        height: 20,
        quality: 80,
      ),
    );
    expect(first, isNotNull);

    await tester.runAsync(() => edgeCompressor.dispose());

    final second = await tester.runAsync(
      () => edgeCompressor.compressToJpeg(
        rgba,
        width: 20,
        height: 20,
        quality: 80,
      ),
    );
    expect(second, isNotNull, reason: 'Should work after dispose');

    await tester.runAsync(() => edgeCompressor.dispose());
  });
}

/// Deterministic widget that produces identical RGBA output across runs.
/// Uses only solid colors, gradients, and shapes — no randomness.
class DeterministicTestScene extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stripeWidth = size.width / 3;

    // Red stripe (left third)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, stripeWidth, size.height),
      Paint()..color = Colors.red,
    );

    // Green stripe (middle third)
    canvas.drawRect(
      Rect.fromLTWH(stripeWidth, 0, stripeWidth, size.height),
      Paint()..color = Colors.green,
    );

    // Blue stripe (right third)
    canvas.drawRect(
      Rect.fromLTWH(stripeWidth * 2, 0, stripeWidth, size.height),
      Paint()..color = Colors.blue,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// GlobalKey used to find our specific RepaintBoundary.
final _boundaryKey = GlobalKey();

/// Captures the keyed RepaintBoundary as raw RGBA bytes.
Future<(Uint8List rgbaBytes, int width, int height)> captureRgba() async {
  final boundary =
      _boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;

  final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
  final ByteData? byteData = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  final width = image.width;
  final height = image.height;
  image.dispose();

  return (byteData!.buffer.asUint8List(), width, height);
}

/// Computes the mean absolute error between two images decoded from JPEG bytes.
/// Returns the average per-channel difference (0-255 scale).
double computeMeanAbsoluteError(Uint8List jpegA, Uint8List jpegB) {
  final imageA = img.decodeJpg(jpegA)!;
  final imageB = img.decodeJpg(jpegB)!;

  if (imageA.width != imageB.width || imageA.height != imageB.height) {
    throw ArgumentError(
      'Image dimensions differ: '
      '${imageA.width}x${imageA.height} vs ${imageB.width}x${imageB.height}',
    );
  }

  var totalDiff = 0;
  var pixelCount = 0;

  for (var y = 0; y < imageA.height; y++) {
    for (var x = 0; x < imageA.width; x++) {
      final pixelA = imageA.getPixel(x, y);
      final pixelB = imageB.getPixel(x, y);

      totalDiff += (pixelA.r.toInt() - pixelB.r.toInt()).abs();
      totalDiff += (pixelA.g.toInt() - pixelB.g.toInt()).abs();
      totalDiff += (pixelA.b.toInt() - pixelB.b.toInt()).abs();
      pixelCount++;
    }
  }

  // Mean absolute error per channel
  return totalDiff / (pixelCount * 3);
}

/// Returns the platform-specific golden reference directory name.
String get platformName {
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  if (Platform.isMacOS) return 'macos';
  return 'unknown';
}

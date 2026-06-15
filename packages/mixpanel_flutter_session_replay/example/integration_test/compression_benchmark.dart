import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/screenshot_capturer.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/native_image_compressor.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';
import 'package:mixpanel_flutter_session_replay/src/models/results.dart';

/// Runs the compression benchmark on the current widget tree.
///
/// Finds the first [RenderRepaintBoundary], iterates all [CompressionMode]s,
/// and prints timing + size results.
Future<void> runBenchmark(
  WidgetTester tester, {
  required String label,
  int iterations = 10,
}) async {
  final boundary = tester.allRenderObjects
      .whereType<RenderRepaintBoundary>()
      .first;

  final logger = MixpanelLogger(LogLevel.info);
  final nativeCompressor = NativeImageCompressor();

  final results = <CompressionMode, List<int>>{
    for (final mode in CompressionMode.values) mode: [],
  };
  final sizes = <CompressionMode, int>{};

  for (final mode in CompressionMode.values) {
    final capturer = ScreenshotCapturer(
      directive: MaskingDirective(autoMaskTypes: {}),
      logger: logger,
      debugOverlayEnabled: false,
      nativeCompressor: nativeCompressor,
      compressionMode: mode,
    );

    // Helper: start capture, pump frame for endOfFrame, then await result
    Future<CaptureResult?> runCapture() async {
      final future = tester.runAsync(() => capturer.capture(boundary));
      await tester.pump();
      return await future;
    }

    // Warmup run
    await runCapture();

    for (var i = 0; i < iterations; i++) {
      final stopwatch = Stopwatch()..start();
      final result = await runCapture();
      stopwatch.stop();

      expect(result, isNotNull);
      expect(result, isA<CaptureSuccess>());
      final success = result! as CaptureSuccess;
      results[mode]!.add(stopwatch.elapsedMilliseconds);
      sizes[mode] = success.data.length;
    }
  }

  // Print results
  debugPrint('');
  debugPrint('=== $label ($iterations iterations) ===');
  debugPrint('');
  for (final mode in CompressionMode.values) {
    final times = results[mode]!;
    if (times.isEmpty) continue;
    times.sort();
    final avg = times.reduce((a, b) => a + b) / times.length;
    final median = times[times.length ~/ 2];
    final min = times.first;
    final max = times.last;
    final sizeKB = (sizes[mode]! / 1024).toStringAsFixed(1);

    debugPrint(
      '${mode.name.padRight(12)} | '
      'avg: ${avg.toStringAsFixed(1).padLeft(6)}ms | '
      'median: ${median.toString().padLeft(4)}ms | '
      'min: ${min.toString().padLeft(4)}ms | '
      'max: ${max.toString().padLeft(4)}ms | '
      'size: ${sizeKB.padLeft(6)}KB',
    );
  }
  debugPrint('');
}

/// CustomPainter that draws photo-like content with many unique colors,
/// gradients, and noise patterns — content where JPEG outperforms PNG.
class PhotoLikePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(42); // Fixed seed for reproducibility

    // Background: complex multi-stop radial gradient
    final bgPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.4),
        radius: 1.5,
        colors: const [
          Color(0xFF1A5276),
          Color(0xFF2E86C1),
          Color(0xFF85C1E9),
          Color(0xFFF9E79F),
          Color(0xFFF39C12),
          Color(0xFFE74C3C),
        ],
        stops: const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Layer 1: Many small rectangles with pseudo-random colors (simulates photo noise)
    final blockSize = 8.0;
    for (var y = 0.0; y < size.height; y += blockSize) {
      for (var x = 0.0; x < size.width; x += blockSize) {
        final paint = Paint()
          ..color = Color.fromARGB(
            40 + random.nextInt(60), // Semi-transparent
            random.nextInt(256),
            random.nextInt(256),
            random.nextInt(256),
          );
        canvas.drawRect(Rect.fromLTWH(x, y, blockSize, blockSize), paint);
      }
    }

    // Layer 2: Overlapping translucent circles (simulates bokeh / depth)
    for (var i = 0; i < 30; i++) {
      final cx = random.nextDouble() * size.width;
      final cy = random.nextDouble() * size.height;
      final radius = 20.0 + random.nextDouble() * 80.0;
      final paint = Paint()
        ..color = Color.fromARGB(
          30 + random.nextInt(80),
          random.nextInt(256),
          random.nextInt(256),
          random.nextInt(256),
        );
      canvas.drawCircle(Offset(cx, cy), radius, paint);
    }

    // Layer 3: Smooth linear gradient overlay (simulates sky/lighting)
    final overlayPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x40FFD700), Color(0x00000000), Color(0x30003366)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, overlayPaint);

    // Layer 4: Fine-grained noise (1px dots scattered across canvas)
    for (var i = 0; i < 5000; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final paint = Paint()
        ..color = Color.fromARGB(
          60 + random.nextInt(120),
          random.nextInt(256),
          random.nextInt(256),
          random.nextInt(256),
        )
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      canvas.drawPoints(ui.PointMode.points, [Offset(x, y)], paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Compression benchmark: UI vs photo-like content', (
    tester,
  ) async {
    // ---- Scene 1: UI widgets (solid colors, sharp edges) ----
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    height: 200,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue, Colors.purple, Colors.red],
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        'Compression Benchmark',
                        style: TextStyle(
                          fontSize: 32,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Wrap(
                    children: List.generate(
                      48,
                      (i) => Container(
                        width: 80,
                        height: 80,
                        margin: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.primaries[i % Colors.primaries.length],
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(64),
                              blurRadius: 4,
                              offset: const Offset(2, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            'Item $i',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Lorem ipsum dolor sit amet, consectetur adipiscing elit. '
                      'Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. '
                      'Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await runBenchmark(tester, label: 'UI Widgets');

    // ---- Scene 2: Photo-like content (gradients, noise, many colors) ----
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            child: SizedBox.expand(
              child: CustomPaint(painter: PhotoLikePainter()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await runBenchmark(tester, label: 'Photo-like Content');
  });
}

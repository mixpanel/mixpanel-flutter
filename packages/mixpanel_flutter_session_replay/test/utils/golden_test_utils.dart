import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/results.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/screenshot_capturer.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';

/// Whether the test font has been loaded in this test run.
bool _fontLoaded = false;

/// Loads the Roboto font for use in golden tests.
///
/// Flutter tests use the Ahem font by default, which renders all glyphs as
/// squares. Loading a real font makes golden test images readable.
Future<void> loadTestFont() async {
  if (_fontLoaded) return;
  final fontData = File('test/fonts/Roboto-Regular.ttf').readAsBytesSync();
  final fontLoader = FontLoader('Roboto')
    ..addFont(Future.value(ByteData.view(fontData.buffer)));
  await fontLoader.load();
  _fontLoaded = true;
}

/// Create a colored square image for testing
///
/// Uses Flutter's createTestImage as base but adds color for visual distinction
Future<ui.Image> createColoredSquareImage({
  int size = 50,
  Color color = Colors.blue,
}) async {
  // Use canvas painting to create colored squares since Flutter's
  // createTestImage only creates transparent/black images
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()..color = color;
  canvas.drawRect(Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()), paint);
  final picture = recorder.endRecording();
  return await picture.toImage(size, size);
}

/// Captures a golden test image of a widget with masking applied
///
/// This helper wraps the widget in MaterialApp + Scaffold scaffolding
/// and uses the production Recorder to capture with masking applied.
///
/// Example:
/// ```dart
/// testWidgets('TextField masking', (tester) async {
///   await captureGolden(
///     tester,
///     TextField(controller: TextEditingController(text: 'test@example.com')),
///     'textfield_masked.png',
///     {AutoMaskedView.text},
///   );
/// });
/// ```
Future<void> captureGolden(
  WidgetTester tester,
  Widget widget,
  String goldenFileName,
  Set<AutoMaskedView> maskTypes, {
  double width = 300,
  double height = 200,
}) async {
  // Load a real font so text renders as readable glyphs instead of Ahem squares
  await loadTestFont();

  // Wrap widget in standard scaffolding with sizing
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Roboto'),
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: RepaintBoundary(
            child: SizedBox(
              width: width,
              height: height,
              child: Align(alignment: Alignment.center, child: widget),
            ),
          ),
        ),
      ),
    ),
  );

  // Pump a few times to ensure widget is fully built
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));

  // Find the RepaintBoundary we created
  final RenderRepaintBoundary boundary = tester.allRenderObjects
      .whereType<RenderRepaintBoundary>()
      .first;

  // Create screenshot capturer with the test's masking directive
  final capturer = ScreenshotCapturer(
    directive: MaskingDirective(autoMaskTypes: maskTypes),
    logger: MixpanelLogger(LogLevel.none),
    debugOverlayEnabled: false,
    compressionMode: CompressionMode.dartPng,
  );

  // Use runAsync to allow the capture's endOfFrame to complete
  // We need to pump frames while capture is running
  late final Uint8List pngBytes;

  // Start capture in background
  final captureFuture = tester.runAsync(() async {
    final result = await capturer.capture(boundary);

    // Verify capture succeeded
    if (result is! CaptureSuccess) {
      final failure = result as CaptureFailure;
      throw Exception('Capture failed: ${failure.errorMessage}');
    }

    return result.data;
  });

  // Pump frames to allow endOfFrame to complete
  await tester.pump();

  // Wait for capture to complete
  final result = await captureFuture;
  if (result == null) {
    throw Exception('Capture returned null');
  }
  pngBytes = result;

  // Handle golden file
  final goldenFile = File('test/golden/$goldenFileName');

  if (!goldenFile.parent.existsSync()) {
    goldenFile.parent.createSync(recursive: true);
  }

  if (!goldenFile.existsSync()) {
    goldenFile.writeAsBytesSync(pngBytes);
    // ignore: avoid_print
    print(
      '📸 Created: $goldenFileName (${(pngBytes.length / 1024).toStringAsFixed(1)}KB)',
    );
  } else {
    final goldenBytes = goldenFile.readAsBytesSync();

    // PNG is deterministic - expect EXACT match
    expect(
      pngBytes,
      equals(goldenBytes),
      reason:
          'Screenshot must exactly match golden file\n'
          'Golden: ${goldenBytes.length} bytes\n'
          'Current: ${pngBytes.length} bytes\n'
          'Delete test/golden/$goldenFileName to regenerate',
    );

    // ignore: avoid_print
    print(
      '✅ Exact match: $goldenFileName (${(pngBytes.length / 1024).toStringAsFixed(1)}KB)',
    );
  }
}

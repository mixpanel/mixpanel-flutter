@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web/web.dart' as web;

const _iterations = 5;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('measures toImage cost at fixed 4K logical complexity', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(3840, 2160);
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(key: key, child: const _BenchmarkScene()),
      ),
    );
    await tester.pumpAndSettle();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

    final results = <String, Object?>{
      'browser': web.window.navigator.userAgent,
      'logical_size': '3840x2160',
      'scene_cards': 72,
      'control': await _measureControl(),
    };
    // Measure the production ratio first so its result does not benefit from a
    // full-resolution capture warming CanvasKit's surface allocation path.
    for (final ratio in const [0.25, 1.0, 0.125, 0.5]) {
      final result = await _measureRatio(tester, boundary, ratio);
      results['ratio_$ratio'] = result;
      debugPrint('TO_IMAGE_SCALE ${jsonEncode({'ratio_$ratio': result})}');
    }
    binding.reportData = results;
  });
}

Future<Map<String, Object>> _measureControl() async {
  final monitor = _RafMonitor()..start();
  await Future<void>.delayed(const Duration(milliseconds: 700));
  return monitor.stop();
}

Future<Map<String, Object>> _measureRatio(
  WidgetTester tester,
  RenderRepaintBoundary boundary,
  double ratio,
) async {
  final cold = Stopwatch()..start();
  final coldImage = await boundary.toImage(pixelRatio: ratio);
  cold.stop();
  final width = coldImage.width;
  final height = coldImage.height;
  coldImage.dispose();

  final monitor = _RafMonitor()..start();
  final samples = <int>[];
  await Future<void>.delayed(const Duration(milliseconds: 100));
  for (var i = 0; i < _iterations; i++) {
    final stopwatch = Stopwatch()..start();
    final pending = tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: ratio);
      image.dispose();
    });
    await tester.pump();
    await pending;
    stopwatch.stop();
    samples.add(stopwatch.elapsedMicroseconds);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  await Future<void>.delayed(const Duration(milliseconds: 100));
  samples.sort();
  return {
    'raster_size': '${width}x$height',
    'cold_us': cold.elapsedMicroseconds,
    'median_us': samples[samples.length ~/ 2],
    'max_us': samples.last,
    ...monitor.stop(),
  };
}

class _RafMonitor {
  final List<double> _timestamps = [];
  JSFunction? _callback;
  int? _requestId;

  void start() {
    void onFrame(num timestamp) {
      _timestamps.add(timestamp.toDouble());
      _requestId = web.window.requestAnimationFrame(_callback!);
    }

    _callback = onFrame.toJS;
    _requestId = web.window.requestAnimationFrame(_callback!);
  }

  Map<String, Object> stop() {
    final requestId = _requestId;
    if (requestId != null) web.window.cancelAnimationFrame(requestId);
    final gaps = <double>[
      for (var i = 1; i < _timestamps.length; i++)
        _timestamps[i] - _timestamps[i - 1],
    ]..sort();
    return {
      'raf_samples': gaps.length,
      'max_raf_gap_ms': gaps.isEmpty ? 0 : gaps.last,
      'p95_raf_gap_ms': gaps.isEmpty
          ? 0
          : gaps[((gaps.length - 1) * 0.95).round()],
      'estimated_dropped_frames': gaps.fold<int>(
        0,
        (total, gap) =>
            total + ((gap / (1000 / 60)).round() - 1).clamp(0, 1000),
      ),
    };
  }
}

class _BenchmarkScene extends StatelessWidget {
  const _BenchmarkScene();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        mainAxisExtent: 150,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: 72,
      itemBuilder: (context, index) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_graph,
                    color: Colors.primaries[index % Colors.primaries.length],
                  ),
                  const Spacer(),
                  Text('${20 + index}%'),
                ],
              ),
              const SizedBox(height: 8),
              Text('Metric $index'),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: ((index % 9) + 1) / 10),
              const Spacer(),
              Text('Updated ${index + 1} minutes ago'),
            ],
          ),
        ),
      ),
    ),
  );
}

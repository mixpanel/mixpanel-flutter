import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/masking/mask_detector.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';

const _rowCount = 250;
const _warmUpIterations = 20;
const _measuredIterations = 100;

void main() {
  testWidgets('measures optimized mask detection', (tester) async {
    // GIVEN a large, fully built widget tree representative of a complex page.
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: boundaryKey,
              child: Column(
                children: List.generate(
                  _rowCount,
                  (index) => Row(
                    children: [
                      const Icon(Icons.shopping_bag),
                      Expanded(child: Text('Product $index')),
                      Text('\$${index + 1}.99'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final boundaryElement = boundaryKey.currentContext! as Element;
    final boundary = boundaryElement.renderObject! as RenderRepaintBoundary;
    final detector = MaskDetector(
      directive: MaskingDirective(
        autoMaskTypes: const {AutoMaskedView.text, AutoMaskedView.image},
      ),
    );

    // Warm the optimized path before collecting samples.
    for (var i = 0; i < _warmUpIterations; i++) {
      detector.detectMaskRegions(boundary, boundaryElement: boundaryElement);
    }

    final samples = <int>[];
    for (var i = 0; i < _measuredIterations; i++) {
      samples.add(
        _measureMicros(() {
          detector.detectMaskRegions(
            boundary,
            boundaryElement: boundaryElement,
          );
        }),
      );
    }

    final stats = _BenchmarkStats(samples);

    // This is intentionally output rather than a timing assertion: absolute
    // timings vary by host, while the two paths remain directly comparable.
    // ignore: avoid_print
    print(
      'Mask detection benchmark ($_rowCount rows, '
      '$_measuredIterations iterations)',
    );
    // ignore: avoid_print
    print('  optimized detection: ${stats.summary}');
  });
}

int _measureMicros(VoidCallback operation) {
  final stopwatch = Stopwatch()..start();
  operation();
  stopwatch.stop();
  return stopwatch.elapsedMicroseconds;
}

class _BenchmarkStats {
  _BenchmarkStats(List<int> samples)
    : _sortedSamples = [...samples]..sort(),
      meanMicros =
          samples.reduce((left, right) => left + right) / samples.length;

  final List<int> _sortedSamples;
  final double meanMicros;

  int get medianMicros => _percentile(0.50);
  int get p95Micros => _percentile(0.95);

  String get summary =>
      'mean=${_formatMicros(meanMicros)}, '
      'median=${_formatMicros(medianMicros)}, '
      'p95=${_formatMicros(p95Micros)}';

  int _percentile(double percentile) {
    final index = math.min(
      (_sortedSamples.length * percentile).ceil() - 1,
      _sortedSamples.length - 1,
    );
    return _sortedSamples[index];
  }
}

String _formatMicros(num microseconds) =>
    '${(microseconds / 1000).toStringAsFixed(3)}ms';

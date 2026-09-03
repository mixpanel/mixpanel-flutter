@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/masking/mask_detector.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';

const _rowCount = int.fromEnvironment('MASK_BENCHMARK_ROWS', defaultValue: 250);
const _warmUpIterations = int.fromEnvironment(
  'MASK_BENCHMARK_WARMUPS',
  defaultValue: 20,
);
const _measuredIterations = int.fromEnvironment(
  'MASK_BENCHMARK_ITERATIONS',
  defaultValue: 100,
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('should measure mask detection when running on device', (
    tester,
  ) async {
    // GIVEN a fully built, scrollable product list inside the capture boundary.
    final boundaryKey = GlobalKey();
    runApp(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: boundaryKey,
            child: SingleChildScrollView(
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
    // Use the device's real frame loop. WidgetTester.pump can wait indefinitely
    // under flutter drive in profile mode on older Android devices.
    await Future<void>.delayed(const Duration(seconds: 1));
    debugPrint('Mask benchmark scene ready ($_rowCount rows)');

    final boundaryElement = boundaryKey.currentContext! as Element;
    final boundary = boundaryElement.renderObject! as RenderRepaintBoundary;
    final detector = MaskDetector(
      directive: MaskingDirective(
        autoMaskTypes: const {AutoMaskedView.text, AutoMaskedView.image},
      ),
    );

    // Warm the optimized path before collecting samples. Run in profile
    // mode so these iterations warm caches rather than the debug JIT compiler.
    for (var i = 0; i < _warmUpIterations; i++) {
      detector.detectMaskRegions(boundary, boundaryElement: boundaryElement);
    }
    debugPrint(
      'Mask benchmark warmup complete ($_warmUpIterations iterations)',
    );

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
    debugPrint(
      'Mask benchmark sampling complete ($_measuredIterations iterations)',
    );

    final stats = _BenchmarkStats(samples);
    final view = tester.view;
    final result = <String, Object>{
      'platform': Platform.operatingSystem,
      'operatingSystemVersion': Platform.operatingSystemVersion,
      'buildMode': _buildMode,
      'logicalWidth': view.physicalSize.width / view.devicePixelRatio,
      'logicalHeight': view.physicalSize.height / view.devicePixelRatio,
      'devicePixelRatio': view.devicePixelRatio,
      'rows': _rowCount,
      'warmups': _warmUpIterations,
      'iterations': _measuredIterations,
      'optimizedDetection': stats.toJson(),
    };

    debugPrint('');
    debugPrint(
      'Mask detection device benchmark '
      '(${Platform.operatingSystem}, $_buildMode, $_rowCount rows)',
    );
    debugPrint('  optimized detection: ${stats.summary}');
    debugPrint('MASK_DETECTION_BENCHMARK_JSON=${jsonEncode(result)}');
    debugPrint('');
  });
}

int _measureMicros(VoidCallback operation) {
  final stopwatch = Stopwatch()..start();
  operation();
  stopwatch.stop();
  return stopwatch.elapsedMicroseconds;
}

String get _buildMode {
  if (kReleaseMode) return 'release';
  if (kProfileMode) return 'profile';
  return 'debug';
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
  int get minimumMicros => _sortedSamples.first;
  int get maximumMicros => _sortedSamples.last;

  String get summary =>
      'mean=${_formatMicros(meanMicros)}, '
      'median=${_formatMicros(medianMicros)}, '
      'p95=${_formatMicros(p95Micros)}, '
      'min=${_formatMicros(minimumMicros)}, '
      'max=${_formatMicros(maximumMicros)}';

  Map<String, num> toJson() => {
    'meanMicros': meanMicros,
    'medianMicros': medianMicros,
    'p95Micros': p95Micros,
    'minimumMicros': minimumMicros,
    'maximumMicros': maximumMicros,
  };

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

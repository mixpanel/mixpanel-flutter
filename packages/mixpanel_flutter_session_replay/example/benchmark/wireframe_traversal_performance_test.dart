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

const _rowCount = int.fromEnvironment(
  'WIREFRAME_BENCHMARK_ROWS',
  defaultValue: 250,
);
const _warmUpPairs = int.fromEnvironment(
  'WIREFRAME_BENCHMARK_WARMUPS',
  defaultValue: 20,
);
const _measuredPairs = int.fromEnvironment(
  'WIREFRAME_BENCHMARK_ITERATIONS',
  defaultValue: 100,
);
const _maximumP95DeltaMicros = int.fromEnvironment(
  'WIREFRAME_MAX_P95_DELTA_US',
  defaultValue: 2000,
);
const _frameBudgetMicros = int.fromEnvironment(
  'WIREFRAME_FRAME_BUDGET_US',
  defaultValue: 16667,
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('should keep wireframe traversal within the frame budget', (
    tester,
  ) async {
    final boundaryKey = GlobalKey();
    runApp(_BenchmarkScene(boundaryKey: boundaryKey));
    await Future<void>.delayed(const Duration(seconds: 1));

    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final boundaryElement = boundaryKey.currentContext! as Element;
    final directive = MaskingDirective(
      autoMaskTypes: const {AutoMaskedView.text, AutoMaskedView.image},
    );
    final withoutWireframes = MaskDetector(directive: directive);
    final withWireframes = MaskDetector(
      directive: directive,
      collectWireframes: true,
    );

    for (var i = 0; i < _warmUpPairs; i++) {
      withoutWireframes.detectMaskRegions(
        boundary,
        boundaryElement: boundaryElement,
      );
      withWireframes.detectMaskRegions(
        boundary,
        boundaryElement: boundaryElement,
      );
    }

    final disabledSamples = <int>[];
    final enabledSamples = <int>[];
    final pairedDeltas = <int>[];
    MaskDetectionResult? disabledResult;
    MaskDetectionResult? enabledResult;
    for (var i = 0; i < _measuredPairs; i++) {
      late final int disabledMicros;
      late final int enabledMicros;
      if (i.isEven) {
        (disabledMicros, disabledResult) = _measure(
          () => withoutWireframes.detectMaskRegions(
            boundary,
            boundaryElement: boundaryElement,
          ),
        );
        (enabledMicros, enabledResult) = _measure(
          () => withWireframes.detectMaskRegions(
            boundary,
            boundaryElement: boundaryElement,
          ),
        );
      } else {
        (enabledMicros, enabledResult) = _measure(
          () => withWireframes.detectMaskRegions(
            boundary,
            boundaryElement: boundaryElement,
          ),
        );
        (disabledMicros, disabledResult) = _measure(
          () => withoutWireframes.detectMaskRegions(
            boundary,
            boundaryElement: boundaryElement,
          ),
        );
      }
      disabledSamples.add(disabledMicros);
      enabledSamples.add(enabledMicros);
      pairedDeltas.add(enabledMicros - disabledMicros);
    }

    if (enabledResult == null || disabledResult == null) {
      fail('benchmark produced no samples');
    }
    expect(enabledResult.rawWireframes, isNotEmpty);
    expect(disabledResult.rawWireframes, isNull);
    // Wireframes are observational only: opting in must not alter mask bounds,
    // ordering, or provenance. This guards the existing screenshot privacy path.
    expect(enabledResult.maskRegions, disabledResult.maskRegions);
    expect(enabledResult.shouldSkipCapture, disabledResult.shouldSkipCapture);

    final disabled = _Stats(disabledSamples);
    final enabled = _Stats(enabledSamples);
    final delta = _Stats(pairedDeltas);
    final result = <String, Object>{
      'platform': Platform.operatingSystem,
      'operatingSystemVersion': Platform.operatingSystemVersion,
      'buildMode': _buildMode,
      'rows': _rowCount,
      'warmupPairs': _warmUpPairs,
      'measuredPairs': _measuredPairs,
      'disabled': disabled.toJson(),
      'enabled': enabled.toJson(),
      'pairedDelta': delta.toJson(),
      'guardrails': {
        'maximumP95DeltaMicros': _maximumP95DeltaMicros,
        'frameBudgetMicros': _frameBudgetMicros,
      },
    };

    debugPrint(
      'Wireframe traversal benchmark (${Platform.operatingSystem}, $_buildMode)',
    );
    debugPrint('  disabled: ${disabled.summary}');
    debugPrint('  enabled:  ${enabled.summary}');
    debugPrint('  paired delta: ${delta.summary}');
    debugPrint('WIREFRAME_TRAVERSAL_BENCHMARK_JSON=${jsonEncode(result)}');

    expect(
      delta.p95Micros,
      lessThanOrEqualTo(_maximumP95DeltaMicros),
      reason: 'wireframes added more than 2 ms at p95',
    );
    expect(
      enabled.p95Micros,
      lessThan(_frameBudgetMicros),
      reason: 'wireframe-enabled traversal exhausted a 60 Hz frame budget',
    );
  });
}

(int, T) _measure<T>(T Function() operation) {
  final stopwatch = Stopwatch()..start();
  final result = operation();
  stopwatch.stop();
  return (stopwatch.elapsedMicroseconds, result);
}

String get _buildMode {
  if (kReleaseMode) return 'release';
  if (kProfileMode) return 'profile';
  return 'debug';
}

class _BenchmarkScene extends StatelessWidget {
  const _BenchmarkScene({required this.boundaryKey});

  final GlobalKey boundaryKey;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: RepaintBoundary(
        key: boundaryKey,
        child: SingleChildScrollView(
          child: Column(
            children: List.generate(
              _rowCount,
              (index) => SizedBox(
                height: 48,
                child: Row(
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
}

class _Stats {
  _Stats(List<int> samples)
    : _sorted = [...samples]..sort(),
      meanMicros = samples.reduce((a, b) => a + b) / samples.length;

  final List<int> _sorted;
  final double meanMicros;

  int get medianMicros => _percentile(0.50);
  int get p95Micros => _percentile(0.95);
  int get minimumMicros => _sorted.first;
  int get maximumMicros => _sorted.last;

  String get summary =>
      'median=${_milliseconds(medianMicros)}, '
      'p95=${_milliseconds(p95Micros)}, '
      'mean=${_milliseconds(meanMicros)}, '
      'min=${_milliseconds(minimumMicros)}, '
      'max=${_milliseconds(maximumMicros)}';

  Map<String, num> toJson() => {
    'meanMicros': meanMicros,
    'medianMicros': medianMicros,
    'p95Micros': p95Micros,
    'minimumMicros': minimumMicros,
    'maximumMicros': maximumMicros,
  };

  int _percentile(double value) =>
      _sorted[math.min(
        (_sorted.length * value).ceil() - 1,
        _sorted.length - 1,
      )];
}

String _milliseconds(num micros) => '${(micros / 1000).toStringAsFixed(3)}ms';

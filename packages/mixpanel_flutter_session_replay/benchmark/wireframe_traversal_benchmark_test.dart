import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/masking/mask_detector.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';

const _rowCount = 250;
const _warmUpPairs = 20;
const _measuredPairs = 100;

void main() {
  testWidgets('should report incremental wireframe traversal cost', (
    tester,
  ) async {
    // GIVEN a large, fully built hierarchy representative of a complex screen.
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(_BenchmarkScene(boundaryKey: boundaryKey));
    await tester.pump();

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

    // Alternate order so cache, scheduler, and thermal drift affect both paths.
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
    expect(
      enabledResult.maskRegions,
      hasLength(disabledResult.maskRegions.length),
    );
    expect(enabledResult.shouldSkipCapture, disabledResult.shouldSkipCapture);

    final result = _BenchmarkResult(
      disabled: _Stats(disabledSamples),
      enabled: _Stats(enabledSamples),
      delta: _Stats(pairedDeltas),
    );

    // Host numbers are diagnostic only. The profile-mode device benchmark owns
    // the pass/fail frame-budget guardrails.
    // ignore: avoid_print
    print(result.summary);
    // ignore: avoid_print
    print('WIREFRAME_TRAVERSAL_BENCHMARK_JSON=${jsonEncode(result.toJson())}');
  });
}

(int, T) _measure<T>(T Function() operation) {
  final stopwatch = Stopwatch()..start();
  final result = operation();
  stopwatch.stop();
  return (stopwatch.elapsedMicroseconds, result);
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

class _BenchmarkResult {
  const _BenchmarkResult({
    required this.disabled,
    required this.enabled,
    required this.delta,
  });

  final _Stats disabled;
  final _Stats enabled;
  final _Stats delta;

  String get summary =>
      'Wireframe traversal benchmark ($_rowCount rows, $_measuredPairs pairs)\n'
      '  disabled: ${disabled.summary}\n'
      '  enabled:  ${enabled.summary}\n'
      '  paired delta: ${delta.summary}';

  Map<String, Object> toJson() => {
    'rows': _rowCount,
    'warmupPairs': _warmUpPairs,
    'measuredPairs': _measuredPairs,
    'disabled': disabled.toJson(),
    'enabled': enabled.toJson(),
    'pairedDelta': delta.toJson(),
  };
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

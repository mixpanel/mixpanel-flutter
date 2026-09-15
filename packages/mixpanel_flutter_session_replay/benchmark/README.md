# Mask detection benchmarks

The benchmarks measure mask detection over a large, fully built widget tree.
They intentionally do not assert timing thresholds because absolute performance
varies by host and device. Recorded paired experiments below preserve the
before/after evidence for individual optimizations.

## Host benchmark

From `packages/mixpanel_flutter_session_replay`:

```bash
flutter test benchmark/mask_detection_benchmark_test.dart
```

## Android device benchmark

Use a profile build so debug logging and JIT compilation do not dominate the
measurement. From `packages/mixpanel_flutter_session_replay/example`:

```bash
flutter devices
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/mask_detection_performance_test.dart \
  -d <device-id> \
  --profile
```

The test prints a human-readable summary and a line beginning with
`MASK_DETECTION_BENCHMARK_JSON=` for archival or automated comparison.

The scene size and sample counts can be overridden when testing particularly
slow hardware:

```bash
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/mask_detection_performance_test.dart \
  -d <device-id> \
  --profile \
  --dart-define=MASK_BENCHMARK_ROWS=250 \
  --dart-define=MASK_BENCHMARK_WARMUPS=20 \
  --dart-define=MASK_BENCHMARK_ITERATIONS=100
```

For comparable runs, keep the device plugged in, close other applications, let
the device cool between runs, and record the model and Android version:

```bash
adb -s <device-id> shell getprop ro.product.model
adb -s <device-id> shell getprop ro.build.version.release
```

Run each branch at least five times on the same device and compare medians and
p95 values rather than a single run.

## Boundary lookup experiment

The following profile-mode sample was collected on a Nexus 5X running Android
8.1.0 (`OPM6.171019.030.B1`). Each run used 250 rows, 20 warm-up iterations,
and 100 measured iterations per path. The two paths were alternated within each
run to limit ordering and thermal bias.

| Run | Legacy median | Direct median | Median change | Legacy p95 | Direct p95 |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 36.677 ms | 36.897 ms | -0.60% | 43.353 ms | 43.286 ms |
| 2 | 45.214 ms | 44.924 ms | +0.64% | 49.027 ms | 48.631 ms |
| 3 | 45.576 ms | 45.335 ms | +0.53% | 49.917 ms | 49.181 ms |
| 4 | 18.884 ms | 18.766 ms | +0.62% | 20.207 ms | 20.091 ms |
| 5 | 18.687 ms | 18.644 ms | +0.23% | 19.989 ms | 20.042 ms |

Positive change means the direct-element path was faster. Its median improvement
across the five paired runs was 0.53%, while absolute medians varied from about
19 ms to 46 ms as the device changed performance state. This indicates that
supplying the known boundary element removes little work: descendant traversal
and mask classification dominate detection time.

## Single-pass and type-check experiment

This experiment combined two changes: detecting unsafe visual states during the
mask traversal instead of walking the Element tree twice, and replacing
per-RenderBox `runtimeType.toString()` classification with Dart type checks for
`RenderParagraph` and `RenderImage`. The legacy and optimized pipelines were
alternated in the same process. All runs produced identical masks and skip
decisions.

| Run | Legacy median | Optimized median | Reduction | Legacy p95 | Optimized p95 |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 16.266 ms | 7.560 ms | 53.52% | 17.573 ms | 8.827 ms |
| 2 | 15.992 ms | 7.453 ms | 53.40% | 17.181 ms | 8.647 ms |
| 3 | 16.017 ms | 7.536 ms | 52.95% | 17.361 ms | 8.792 ms |
| 4 | 15.993 ms | 7.505 ms | 53.07% | 17.244 ms | 8.807 ms |
| 5 | 15.446 ms | 7.483 ms | 51.55% | 16.877 ms | 8.674 ms |

The median paired reduction was 53.07%. The optimized p95 remained below 9 ms
in every run, compared with 16.88-17.57 ms for the legacy pipeline. A host run
measured a 32.1% median reduction (2.421 ms to 1.643 ms).

After removing the in-process legacy comparison code, a final production-path
run measured 6.815 ms median, 7.908 ms p95, and 9.610 ms maximum on the Nexus
5X. The corresponding clean host benchmark measured 1.570 ms median and 1.832
ms p95.

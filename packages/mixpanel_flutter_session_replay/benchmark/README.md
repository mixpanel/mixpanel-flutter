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

# Wireframe traversal performance

These benchmarks measure the incremental UI-isolate cost of enabling wireframe
collection during the hierarchy walk that already performs mask detection. Each
sample pair runs the same production traversal with collection disabled and
enabled, alternates execution order, and verifies that both paths produce the
same masking result.

The release guardrails are:

- p95 paired wireframe overhead must be at most **2 ms**;
- p95 total wireframe-enabled traversal must be below **16.667 ms**.

The host benchmark is useful while developing, but is not release evidence:

```bash
flutter test benchmark/wireframe_traversal_benchmark_test.dart
```

Collect release evidence on both an older Android device and an older iPhone in
profile mode, from the `example` directory. The device harness lives under
`example/benchmark/`, outside Flutter's standard `test/` and `integration_test/`
discovery paths:

```bash
flutter drive \
  --driver=benchmark/integration_test_driver.dart \
  --target=benchmark/wireframe_traversal_performance_test.dart \
  --profile \
  -d <device-id>
```

The test prints `WIREFRAME_TRAVERSAL_BENCHMARK_JSON=...` for archival. Run it
five times per device, let the device cool between runs, and retain every JSON
line with the device model, OS version, commit SHA, and Flutter version. A
release passes only when all five runs satisfy both guardrails.

Raw runs may be saved locally under ignored `benchmark/results/`, including
failures. A run whose
wireframe-disabled p95 already exceeds 16.667 ms is still retained and still
fails: a small incremental overhead does not make the total UI-isolate work fit
inside the frame budget.

## Web capture and upload performance

The web integration harness exercises the production screenshot capture,
worker-side privacy masking and JPEG encoding, IndexedDB queue, worker-side
gzip encoding, and an actual HTTP upload to a local validation server. It runs
three captures against representative 1366×768, 1920×1080, 3840×2160, and
5120×1440 dashboard widget trees while sampling `requestAnimationFrame`. The
4K coverage separates a representative 72-card scene from a deliberately dense
240-card stress scene so viewport resolution and visible-tree complexity are
not conflated. The larger viewports verify the production
1280×720-equivalent raster budget rather than allocating full-resolution RGBA
buffers. Where the browser implements the Long Tasks API, the harness observes
that directly as well.

Each viewport also runs a matched `no_sdk_control` window against the same
rendered scene. It uses the same frame pumps and timing intervals but omits mask
and wireframe traversal, screenshot capture, pixel transfer, and worker work.
This makes capture-induced frame gaps distinguishable from browser scheduling
or test-harness noise in the recorded metrics.

Start the browser's WebDriver on port 4444, then run this from `example`:

```bash
flutter drive -d web-server \
  --browser-name=chrome \
  --browser-dimension=1920x1080 \
  --profile \
  --driver=test_driver/web_validation_test.dart \
  --target=integration_test/web_validation_test.dart \
  --timeout=300
```

Use `firefox` or `safari` for `--browser-name` with GeckoDriver or SafariDriver.
Add `--wasm` to the Chrome command to validate the Dart2Wasm and Skwasm path;
CI runs both Chrome renderers. Flutter's web server supplies the cross-origin
isolation headers needed for multi-threaded Skwasm during this benchmark.
Do not append a device-pixel-ratio suffix such as `@1` for this desktop
benchmark: Flutter implements that option through Chrome mobile emulation and
changes the browser user agent. The test sets its Flutter view DPR explicitly.
The test fails if capture adds more than 24 ms to the baseline maximum rAF gap,
creates a gap over 50 ms, or produces a browser main-thread long task. CI uses
a 34 ms baseline-relative allowance for Firefox and Safari to accommodate
runner-level scheduling variance while retaining the 50 ms hard limit.

Metrics are written to
`example/build/integration_response_data.json`, including maximum and p95 rAF
gaps, an estimated dropped-frame count, Long Tasks support/count/duration, and
end-to-end capture times. Each capture result is paired with a
`<scenario>_no_sdk_control` result. Run at least five times before a release and
retain all outputs; VM or host contention should be visible in the
baseline-relative and p95 measurements rather than silently discarded.

The same run also exercises privacy masking while a transform animation and a
`ListView` scroll concurrently. Saturated magenta test pixels exist only inside
`MixpanelMask` widgets, so the decoded replay JPEG is scanned independently of
Flutter's reported mask coordinates. Captures whose geometry changes across the
browser presentation barrier must be discarded. Six settled fractional scroll
positions are then captured for visual inspection. Exact replay JPEGs and PNG
copies with detected mask coordinates outlined in green are written under
`example/build/web_motion_mask_validation/`.

### Isolated `toImage` scaling diagnostic

The isolated scaling benchmark holds the Flutter scene and its 3840×2160
logical viewport constant, bypasses all session replay traversal, masking,
encoding, storage, and upload work, and changes only the `pixelRatio` passed to
`RenderRepaintBoundary.toImage`. It records cold, median, and maximum capture
times together with animation-frame gaps for ratios 1, 0.5, 0.25, and 0.125.

Run it from `example` with a desktop WebDriver already listening on port 4444:

```bash
flutter drive -d web-server \
  --browser-name=chrome \
  --browser-dimension=1920x1080 \
  --profile \
  --driver=test_driver/to_image_scale_test.dart \
  --target=integration_test/to_image_scale_test.dart \
  --timeout=300
```

Add `--wasm` to isolate the same operation under Skwasm.

This is a diagnostic rather than a pass/fail release guardrail. Compare ratios
within one run; browser, renderer, GPU, and host differences make absolute
timings unsuitable as portable thresholds.

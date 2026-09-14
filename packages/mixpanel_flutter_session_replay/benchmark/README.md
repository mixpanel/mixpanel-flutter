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

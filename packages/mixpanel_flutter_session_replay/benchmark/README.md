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

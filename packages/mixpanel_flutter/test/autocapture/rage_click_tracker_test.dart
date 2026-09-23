import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:mixpanel_flutter/src/autocapture/rage_click_tracker.dart';
import 'package:mixpanel_flutter/src/autocapture/detection_limits.dart';

void main() {
  test('nested options preserve defaults and bounded settings', () {
    const defaults = AutocaptureOptions();
    expect(defaults.clickOptions.enabled, isTrue);
    expect(defaults.rageClickOptions.enabled, isTrue);
    expect(defaults.deadClickOptions.enabled, isTrue);
    expect(defaults.rageClickOptions.clickThreshold, 4);
    expect(defaults.rageClickOptions.timeWindow, const Duration(seconds: 1));
    expect(defaults.rageClickOptions.radius, 44);
    expect(defaults.deadClickOptions.timeWindow,
        const Duration(milliseconds: 500));
    expect(
        const AutocaptureOptions(
          clickOptions: ClickOptions(enabled: false),
          rageClickOptions: RageClickOptions(enabled: false),
          deadClickOptions: DeadClickOptions(enabled: false),
        ).isEnabled,
        isFalse);
  });
  test('Android parity emits only at taps four and eight', () {
    final tracker = RageClickTracker(const RageClickOptions());
    expect(
        List.generate(
            8, (i) => tracker.record(20, 20, Duration(milliseconds: i * 100))),
        [false, false, false, true, false, false, false, true]);
  });
  test('window and radius boundaries include equality', () {
    final tracker = RageClickTracker(const RageClickOptions(clickThreshold: 2));
    expect(tracker.record(0, 0, Duration.zero), false);
    expect(tracker.record(44, 0, const Duration(milliseconds: 1000)), true);
  });
  test('rolling window expires old records and does not chain like JS', () {
    final tracker = RageClickTracker(const RageClickOptions());
    expect(
        List.generate(
            4, (i) => tracker.record(0, 0, Duration(milliseconds: i * 900))),
        [false, false, false, false]);
  });
  test('counts spatial neighbors of current tap, not matching element IDs', () {
    final tracker = RageClickTracker(const RageClickOptions(clickThreshold: 2));
    tracker.record(0, 0, Duration.zero);
    expect(tracker.record(44.01, 0, const Duration(milliseconds: 1)), false);
    expect(tracker.record(45, 0, const Duration(milliseconds: 2)), true);
  });
  test('reset and backwards time cannot reuse old taps', () {
    final tracker = RageClickTracker(const RageClickOptions(clickThreshold: 2));
    tracker.record(0, 0, const Duration(seconds: 2));
    expect(tracker.record(0, 0, const Duration(seconds: 1)), false);
    tracker.reset();
    expect(tracker.record(0, 0, const Duration(seconds: 1)), false);
  });
  test('invalid coordinates are ignored', () {
    final tracker = RageClickTracker(const RageClickOptions());
    expect(tracker.record(double.infinity, 0, Duration.zero), false);
    expect(tracker.record(0, 0, Duration.zero), false);
  });

  test('invalid public scalar settings assert during development', () {
    expect(() => RageClickOptions(clickThreshold: 1), throwsAssertionError);
    expect(() => RageClickOptions(clickThreshold: 101), throwsAssertionError);
    expect(() => RageClickOptions(radius: -1), throwsAssertionError);
    expect(() => RageClickOptions(radius: double.nan), throwsAssertionError);
    expect(
        () => RageClickOptions(radius: double.infinity), throwsAssertionError);
    expect(
        () =>
            RageClickTracker(const RageClickOptions(timeWindow: Duration.zero)),
        throwsAssertionError);
  });

  test('release normalization retains bounds and nonfinite fallback', () {
    expect(normalizeClickThreshold(-1), 2);
    expect(normalizeClickThreshold(101), 100);
    expect(normalizeRadius(double.nan), 44);
    expect(normalizeRadius(double.infinity), 44);
    expect(normalizeRadius(-1), 0);
    expect(normalizeRadius(100001), 100000);
    expect(normalizeTimeWindow(Duration.zero), const Duration(milliseconds: 1));
    expect(normalizeTimeWindow(const Duration(minutes: 2)),
        const Duration(minutes: 1));
    expect(normalizeTimeWindow(const Duration(microseconds: 1500)),
        const Duration(microseconds: 1500));
  });

  test('rage duration preserves microsecond precision at boundary', () {
    final tracker = RageClickTracker(const RageClickOptions(
        clickThreshold: 2, timeWindow: Duration(microseconds: 1500)));
    expect(tracker.record(0, 0, Duration.zero), false);
    expect(tracker.record(0, 0, const Duration(microseconds: 1500)), true);
    expect(tracker.record(0, 0, Duration.zero), false);
    expect(tracker.record(0, 0, const Duration(microseconds: 1501)), false);
  });
}

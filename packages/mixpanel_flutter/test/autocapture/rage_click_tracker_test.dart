import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:mixpanel_flutter/src/autocapture/rage_click_tracker.dart';

void main() {
  test('nested options preserve defaults and bounded settings', () {
    const defaults = AutocaptureOptions();
    expect(defaults.clickOptions.enabled, isTrue);
    expect(defaults.rageClickOptions.enabled, isTrue);
    expect(defaults.deadClickOptions.enabled, isTrue);
    expect(defaults.rageClickOptions.clickThreshold, 4);
    expect(defaults.rageClickOptions.timeWindowMs, 1000);
    expect(defaults.rageClickOptions.radius, 44);
    expect(defaults.deadClickOptions.timeWindowMs, 500);
    expect(const RageClickOptions(clickThreshold: 1000).clickThreshold, 100);
    expect(const RageClickOptions(timeWindowMs: 999999).timeWindowMs, 60000);
    expect(const RageClickOptions(radius: -1).radius, 0);
    expect(const RageClickOptions(radius: 999999).radius, 100000);
    expect(const DeadClickOptions(timeWindowMs: 999999).timeWindowMs, 60000);
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
  test('invalid coordinates are ignored and options are bounded', () {
    const options = RageClickOptions(
        clickThreshold: -1, timeWindowMs: 0, radius: double.nan);
    expect(options.clickThreshold, 2);
    expect(options.timeWindowMs, 1);
    expect(options.radius, 44);
    expect(const DeadClickOptions(timeWindowMs: -5).timeWindowMs, 1);
    final tracker = RageClickTracker(options);
    expect(tracker.record(double.infinity, 0, Duration.zero), false);
    expect(tracker.record(0, 0, Duration.zero), false);
  });
}

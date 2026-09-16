import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:mixpanel_flutter/src/autocapture/rage_click_tracker.dart';

void main() {
  test('Android parity emits only at taps four and eight', () {
    final tracker = RageClickTracker(const AutocaptureOptions());
    expect(
        List.generate(
            8, (i) => tracker.record(20, 20, Duration(milliseconds: i * 100))),
        [false, false, false, true, false, false, false, true]);
  });
  test('window and radius boundaries include equality', () {
    final tracker =
        RageClickTracker(const AutocaptureOptions(rageClickThreshold: 2));
    expect(tracker.record(0, 0, Duration.zero), false);
    expect(tracker.record(44, 0, const Duration(milliseconds: 1000)), true);
  });
  test('rolling window expires old records and does not chain like JS', () {
    final tracker = RageClickTracker(const AutocaptureOptions());
    expect(
        List.generate(
            4, (i) => tracker.record(0, 0, Duration(milliseconds: i * 900))),
        [false, false, false, false]);
  });
  test('counts spatial neighbors of current tap, not matching element IDs', () {
    final tracker =
        RageClickTracker(const AutocaptureOptions(rageClickThreshold: 2));
    tracker.record(0, 0, Duration.zero);
    expect(tracker.record(44.01, 0, const Duration(milliseconds: 1)), false);
    expect(tracker.record(45, 0, const Duration(milliseconds: 2)), true);
  });
  test('reset and backwards time cannot reuse old taps', () {
    final tracker =
        RageClickTracker(const AutocaptureOptions(rageClickThreshold: 2));
    tracker.record(0, 0, const Duration(seconds: 2));
    expect(tracker.record(0, 0, const Duration(seconds: 1)), false);
    tracker.reset();
    expect(tracker.record(0, 0, const Duration(seconds: 1)), false);
  });
  test('invalid coordinates are ignored and options are bounded', () {
    final options = AutocaptureOptions(
        rageClickThreshold: -1,
        rageClickWindowMs: 0,
        rageClickRadius: double.nan,
        deadClickTimeoutMs: -5);
    expect(options.rageClickThreshold, 2);
    expect(options.rageClickWindowMs, 1);
    expect(options.rageClickRadius, 44);
    expect(options.deadClickTimeoutMs, 1);
    final tracker = RageClickTracker(options);
    expect(tracker.record(double.infinity, 0, Duration.zero), false);
    expect(tracker.record(0, 0, Duration.zero), false);
  });
}

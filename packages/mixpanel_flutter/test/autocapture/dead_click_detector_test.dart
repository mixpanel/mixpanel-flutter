import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/src/autocapture/click_event.dart';
import 'package:mixpanel_flutter/src/autocapture/dead_click_detector.dart';
import 'package:mixpanel_flutter/src/autocapture/response_snapshot.dart';

void main() {
  const event = ClickEvent(x: 1, y: 2, elementId: 'target');
  const baseline = ResponseSnapshot(1);
  for (final response in <ResponseSnapshot?>[
    baseline,
    const ResponseSnapshot(2),
    null
  ]) {
    testWidgets(
        'deadline outcome for snapshot ${response == null ? 'unknown' : response.differsFrom(baseline) ? 'changed' : 'unchanged'}',
        (tester) async {
      var count = 0;
      final detector =
          DeadClickDetector(capture: () => response, onDead: (_) => count++);
      detector.begin(baseline);
      detector.arm(event, const Duration(microseconds: 1500));
      expect(detector.observing, isTrue);
      await tester.pump(const Duration(microseconds: 1499));
      expect(count, 0);
      await tester.pump(const Duration(microseconds: 1));
      expect(count, identical(response, baseline) ? 1 : 0);
      expect(detector.observing, isFalse);
    });
  }
  testWidgets('transient response cancellation cannot rearm itself',
      (tester) async {
    var count = 0;
    final detector =
        DeadClickDetector(capture: () => baseline, onDead: (_) => count++);
    detector.begin(baseline);
    detector.arm(event, const Duration(milliseconds: 10));
    expect(detector.observing, isTrue);
    detector.sampleSnapshot(const ResponseSnapshot(2));
    detector.sampleSnapshot(baseline);
    await tester.pump(const Duration(milliseconds: 20));
    expect(count, 0);
  });
  testWidgets('replacement discards old deadline and emits replacement once',
      (tester) async {
    final events = <ClickEvent>[];
    final detector =
        DeadClickDetector(capture: () => baseline, onDead: events.add);
    detector.begin(baseline);
    detector.arm(event, const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 5));
    const replacement = ClickEvent(x: 3, y: 4, elementId: 'replacement');
    detector.begin(baseline);
    detector.arm(replacement, const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 5));
    expect(events, isEmpty);
    await tester.pump(const Duration(milliseconds: 15));
    expect(events, [replacement]);
  });
  testWidgets(
      'scheduled frame defers capture and cancelled callback stays stale',
      (tester) async {
    var captures = 0;
    var emissions = 0;
    final detector = DeadClickDetector(
        capture: () {
          captures++;
          return baseline;
        },
        onDead: (_) => emissions++);
    detector.begin(baseline);
    detector.arm(event, const Duration(milliseconds: 10));
    tester.binding.scheduleFrame();
    int? capturesBeforeFrame;
    Timer(const Duration(milliseconds: 10), () {
      capturesBeforeFrame = captures;
      detector.cancel();
    });
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();
    expect(capturesBeforeFrame, 0);
    expect(captures, 0);
    expect(emissions, 0);
  });
  testWidgets('scheduled frame completes unchanged candidate after rendering',
      (tester) async {
    var emissions = 0;
    final detector =
        DeadClickDetector(capture: () => baseline, onDead: (_) => emissions++);
    detector.begin(baseline);
    detector.arm(event, const Duration(milliseconds: 10));
    tester.binding.scheduleFrame();
    await tester.pump(const Duration(milliseconds: 10));
    expect(emissions, 1);
  });
  testWidgets('unknown baseline never arms and invalid duration asserts',
      (tester) async {
    final detector = DeadClickDetector(
        capture: () => baseline, onDead: (_) => fail('unexpected emission'));
    detector.begin(null);
    detector.arm(event, const Duration(milliseconds: 10));
    expect(detector.observing, isFalse);
    await tester.pump(const Duration(milliseconds: 20));
    expect(() => detector.arm(event, Duration.zero), throwsAssertionError);
  });
  testWidgets('candidate validity suppresses dead even with unchanged snapshot',
      (tester) async {
    var valid = true;
    var emissions = 0;
    final detector = DeadClickDetector(capture: () => baseline);
    detector.begin(baseline);
    detector.arm(event, const Duration(milliseconds: 10),
        isValid: () => valid, onDetected: (_) => emissions++);
    expect(detector.observing, isTrue);
    valid = false;
    await tester.pump(const Duration(milliseconds: 10));
    expect(emissions, 0);
    detector.begin(baseline);
    valid = true;
    detector.arm(event, const Duration(milliseconds: 10),
        isValid: () => valid, onDetected: (_) => emissions++);
    await tester.pump(const Duration(milliseconds: 10));
    expect(emissions, 1);
  });

  testWidgets('deferred old candidate cannot finish its replacement',
      (tester) async {
    final detected = <String>[];
    final detector = DeadClickDetector(capture: () => baseline);
    detector.begin(baseline);
    detector.arm(event, const Duration(milliseconds: 10),
        onDetected: (_) => detected.add('old'));
    tester.binding.scheduleFrame();
    Timer(const Duration(milliseconds: 10), () {
      detector.begin(baseline);
      detector.arm(event, const Duration(milliseconds: 20),
          onDetected: (_) => detected.add('new'));
    });
    await tester.pump(const Duration(milliseconds: 10));
    expect(detected, isEmpty);
    expect(detector.observing, isTrue);
    await tester.pump(const Duration(milliseconds: 20));
    expect(detected, ['new']);
  });
}

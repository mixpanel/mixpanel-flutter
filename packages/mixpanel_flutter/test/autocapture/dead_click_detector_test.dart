import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/src/autocapture/autocapture_options.dart';
import 'package:mixpanel_flutter/src/autocapture/click_event.dart';
import 'package:mixpanel_flutter/src/autocapture/dead_click_detector.dart';
import 'package:mixpanel_flutter/src/autocapture/response_snapshot.dart';
import 'package:mixpanel_flutter/src/autocapture/target_resolver.dart';

void main() {
  const event = ClickEvent(x: 1, y: 2, elementId: 'target');
  const baseline = ResponseSnapshot(1);
  DeadClickDetector detector(ResponseSnapshot? Function() capture,
          {Duration timeout = const Duration(milliseconds: 10),
          bool enabled = true}) =>
      DeadClickDetector(DeadClickOptions(enabled: enabled, timeWindow: timeout),
          capture: capture);

  for (final response in <ResponseSnapshot?>[
    baseline,
    const ResponseSnapshot(2),
    null
  ]) {
    testWidgets(
        'deadline outcome for snapshot ${response == null ? 'unknown' : response.differsFrom(baseline) ? 'changed' : 'unchanged'}',
        (tester) async {
      var count = 0;
      final dead =
          detector(() => response, timeout: const Duration(microseconds: 1500));

      dead.start(baseline, event, (_) => count++);
      await tester.pump(const Duration(microseconds: 1499));
      expect(count, 0);
      await tester.pump(const Duration(microseconds: 1));
      expect(count, identical(response, baseline) ? 1 : 0);
    });
  }
  testWidgets('replacement discards old deadline and emits replacement once',
      (tester) async {
    final events = <ClickEvent>[];
    final dead = detector(() => baseline);

    dead.start(baseline, event, events.add);
    await tester.pump(const Duration(milliseconds: 5));
    const replacement = ClickEvent(x: 3, y: 4, elementId: 'replacement');

    dead.start(baseline, replacement, events.add);
    await tester.pump(const Duration(milliseconds: 5));
    expect(events, isEmpty);
    await tester.pump(const Duration(milliseconds: 5));
    expect(events, [replacement]);
  });
  testWidgets('a tap without a baseline still cancels the pending check',
      (tester) async {
    var emissions = 0;
    final dead = detector(() => baseline);

    dead.start(baseline, event, (_) => emissions++);
    dead.start(null, event, (_) => emissions++);
    await tester.pump(const Duration(milliseconds: 20));
    expect(emissions, 0);
  });
  testWidgets(
      'scheduled frame defers capture and cancelled callback stays stale',
      (tester) async {
    var captures = 0;
    var emissions = 0;
    final dead = detector(() {
      captures++;
      return baseline;
    });

    dead.start(baseline, event, (_) => emissions++);
    tester.binding.scheduleFrame();
    int? capturesBeforeFrame;
    Timer(const Duration(milliseconds: 10), () {
      capturesBeforeFrame = captures;
      dead.cancel();
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
    final dead = detector(() => baseline);

    dead.start(baseline, event, (_) => emissions++);
    tester.binding.scheduleFrame();
    await tester.pump(const Duration(milliseconds: 10));
    expect(emissions, 1);
  });
  test('invalid duration asserts', () {
    expect(() => detector(() => baseline, timeout: Duration.zero),
        throwsAssertionError);
  });
  testWidgets('cancel before the deadline suppresses emission', (tester) async {
    var emissions = 0;
    final dead = detector(() => baseline);

    dead.start(baseline, event, (_) => emissions++);
    await tester.pump(const Duration(milliseconds: 5));
    dead.cancel();
    await tester.pump(const Duration(milliseconds: 10));
    expect(emissions, 0);
  });
  testWidgets('deferred old candidate cannot finish its replacement',
      (tester) async {
    final detected = <String>[];
    final dead = detector(() => baseline);

    dead.start(baseline, event, (_) => detected.add('old'));
    tester.binding.scheduleFrame();
    Timer(const Duration(milliseconds: 10), () {
      dead.start(baseline, event, (_) => detected.add('new'));
    });
    await tester.pump(const Duration(milliseconds: 10));
    expect(detected, isEmpty);
    await tester.pump(const Duration(milliseconds: 10));
    expect(detected, ['new']);
  });
  testWidgets('baseline requires detection enabled and an eligible target',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final element = tester.element(find.byType(SizedBox));
    CaptureTarget target(bool eligible) => CaptureTarget(
        element, const ClickEvent(x: 0, y: 0, elementId: 'id'), eligible);

    expect(detector(() => baseline).baselineFor(target(true)), same(baseline));
    expect(detector(() => baseline).baselineFor(target(false)), isNull);
    expect(detector(() => baseline, enabled: false).baselineFor(target(true)),
        isNull);
  });
}

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/src/autocapture/response_snapshot.dart';
import 'package:mixpanel_flutter/src/autocapture/ui_response_tracker.dart';

void main() {
  const baseline = ResponseSnapshot(1);
  test('comparison distinguishes unchanged changed and unknown', () {
    expect(
        baseline.compare(const ResponseSnapshot(1)), ResponseChange.unchanged);
    expect(baseline.compare(const ResponseSnapshot(2)), ResponseChange.changed);
    expect(baseline.compare(null), ResponseChange.unknown);
  });
  test('changed and unknown observations cannot regain a baseline', () {
    for (final sample in <ResponseSnapshot?>[const ResponseSnapshot(2), null]) {
      final observation = ResponseObservation(baseline)..sample(sample);
      expect(observation.change,
          sample == null ? ResponseChange.unknown : ResponseChange.changed);
      observation.sample(baseline);
      expect(observation.unchangedBaseline, isNull);
    }
    expect(ResponseObservation(null).change, ResponseChange.unknown);
  });
  test('one snapshot serves overlapping press and candidate', () {
    var captures = 0;
    ResponseSnapshot? current = baseline;
    final candidateSnapshots = <ResponseSnapshot?>[];
    final tracker = UiResponseTracker(
        capture: () {
          captures++;
          return current;
        },
        canObserve: () => true,
        hasCandidate: () => true,
        onSnapshot: candidateSnapshots.add,
        onResponse: () {});
    tracker.beginPress();
    current = const ResponseSnapshot(2);
    tracker.sampleFrame();
    expect(captures, 2); // one baseline and one shared frame
    expect(candidateSnapshots, [current]);
    current = baseline;
    tracker.sampleFrame();
    expect(tracker.takeBaseline(), isNull);
  });
  test('idle and disallowed tracking do not capture', () {
    var captures = 0;
    var allowed = true;
    var pending = false;
    final tracker = UiResponseTracker(
        capture: () {
          captures++;
          return baseline;
        },
        canObserve: () => allowed,
        hasCandidate: () => pending,
        onSnapshot: (_) {},
        onResponse: () {});
    tracker.sampleFrame();
    expect(captures, 0);
    pending = true;
    allowed = false;
    tracker.sampleFrame();
    expect(captures, 0);
  });
  test('response and cancel clear press; taking baseline consumes it', () {
    var responses = 0;
    final tracker = UiResponseTracker(
        capture: () => baseline,
        canObserve: () => true,
        hasCandidate: () => false,
        onSnapshot: (_) {},
        onResponse: () => responses++);
    tracker.beginPress();
    tracker.markResponse();
    expect(responses, 1);
    expect(tracker.takeBaseline(), isNull);
    tracker.beginPress();
    tracker.cancelPress();
    expect(tracker.takeBaseline(), isNull);
    tracker.beginPress();
    expect(tracker.takeBaseline(), same(baseline));
    expect(tracker.takeBaseline(), isNull);
  });
  testWidgets(
      'start stop are idempotent and remove frame and metrics callbacks',
      (tester) async {
    var captures = 0;
    var responses = 0;
    final tracker = UiResponseTracker(
        capture: () {
          captures++;
          return baseline;
        },
        canObserve: () => true,
        hasCandidate: () => true,
        onSnapshot: (_) {},
        onResponse: () => responses++);
    tracker.start();
    tracker.start();
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(captures, 1);
    tester.binding.handleMetricsChanged();
    expect(responses, 1);
    tracker.stop();
    tracker.stop();
    tester.binding.handleMetricsChanged();
    await tester.pump();
    expect(responses, 1);
    expect(captures, 1);
    tracker.start();
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(captures, 2);
    tracker.stop();
  });
  testWidgets('scroll update cancels response without consuming notification',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(builder: (value) {
          context = value;
          return const SizedBox();
        })));
    var responses = 0;
    final tracker = UiResponseTracker(
        capture: () => baseline,
        canObserve: () => true,
        hasCandidate: () => false,
        onSnapshot: (_) {},
        onResponse: () => responses++);
    final metrics = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 100,
        pixels: 10,
        viewportDimension: 100,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1);
    tracker.beginPress();
    expect(
        tracker.onScroll(
            ScrollUpdateNotification(metrics: metrics, context: context)),
        isFalse);
    expect(responses, 1);
    expect(tracker.takeBaseline(), isNull);
  });
}

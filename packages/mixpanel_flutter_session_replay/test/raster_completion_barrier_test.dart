import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/capture/raster_completion_barrier.dart';

import 'helpers/raster_test_binding.dart';

void main() {
  RasterTestBinding();
  testWidgets('should require acknowledgement of the observed frame', (
    tester,
  ) async {
    final barrier = RasterCompletionBarrier();
    addTearDown(barrier.dispose);
    final frame = tester.platformDispatcher.frameData.frameNumber;
    bool? acknowledged;
    barrier.waitForCurrentFrame().then((value) => acknowledged = value);

    _report(tester, frame - 1);
    await tester.pump();
    expect(acknowledged, isNull);

    _report(tester, frame);
    await tester.pump();
    expect(acknowledged, isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('should accept newer frames and ignore older reports', (
    tester,
  ) async {
    final barrier = RasterCompletionBarrier();
    addTearDown(barrier.dispose);
    final frame = tester.platformDispatcher.frameData.frameNumber;
    final pending = barrier.waitForCurrentFrame();

    _report(tester, frame + 2);
    expect(await pending, isTrue);
    _report(tester, frame - 1);
    expect(await barrier.waitForCurrentFrame(), isTrue);
  });

  testWidgets('should request a reporting frame only during preparation', (
    tester,
  ) async {
    final barrier = RasterCompletionBarrier();
    addTearDown(barrier.dispose);
    final pending = barrier.prepare();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.binding.delayed(const Duration(milliseconds: 120));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    _report(tester, tester.platformDispatcher.frameData.frameNumber);
    expect(await pending, isTrue);
    await tester.binding.delayed(const Duration(milliseconds: 600));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
    'should finish its requested frame before releasing preparation',
    (tester) async {
      final barrier = RasterCompletionBarrier();
      addTearDown(barrier.dispose);
      bool? acknowledged;
      barrier.prepare().then((value) => acknowledged = value);
      await tester.pump();
      await tester.binding.delayed(const Duration(milliseconds: 120));
      expect(tester.binding.hasScheduledFrame, isTrue);

      // The old frame reports completion while the reporting frame is queued.
      // Its acknowledgement must not let that queued frame run after mask read.
      _report(tester, tester.platformDispatcher.frameData.frameNumber);
      await tester.idle();
      expect(acknowledged, isNull);
      await tester.pump();
      _report(tester, tester.platformDispatcher.frameData.frameNumber);
      await tester.idle();
      expect(acknowledged, isTrue);
    },
  );

  testWidgets('should cancel the reporting frame when acknowledged promptly', (
    tester,
  ) async {
    final barrier = RasterCompletionBarrier();
    addTearDown(barrier.dispose);
    final pending = barrier.prepare();
    await tester.pump();
    _report(tester, tester.platformDispatcher.frameData.frameNumber);
    expect(await pending, isTrue);

    await tester.binding.delayed(const Duration(milliseconds: 600));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('should fail closed without requesting a frame after mask read', (
    tester,
  ) async {
    final barrier = RasterCompletionBarrier();
    addTearDown(barrier.dispose);
    final pending = barrier.waitForCurrentFrame();

    await tester.binding.delayed(const Duration(milliseconds: 500));
    expect(await pending, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);

    // A timeout must not poison a later capture once reports resume.
    _report(tester, tester.platformDispatcher.frameData.frameNumber);
    expect(await barrier.waitForCurrentFrame(), isTrue);
  });

  testWidgets('should bound preparation even when no Flutter frame arrives', (
    tester,
  ) async {
    final barrier = RasterCompletionBarrier();
    addTearDown(barrier.dispose);
    final pending = barrier.prepare();
    await tester.binding.delayed(const Duration(milliseconds: 500));
    expect(await pending, isFalse);

    // A late endOfFrame must not start a new reporting-frame timer.
    await tester.pump();
    await tester.binding.delayed(const Duration(milliseconds: 120));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('should reject pending waits and cancel timers on disposal', (
    tester,
  ) async {
    final barrier = RasterCompletionBarrier();
    final preparing = barrier.prepare();
    await tester.pump();
    final acquiring = barrier.waitForCurrentFrame();

    barrier.dispose();
    barrier.dispose();
    expect(await preparing, isFalse);
    expect(await acquiring, isFalse);
    expect(await barrier.prepare(), isFalse);
    expect(await barrier.waitForCurrentFrame(), isFalse);
    await tester.binding.delayed(const Duration(milliseconds: 600));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('should reject missing frame metadata', (tester) async {
    final dispatcher = tester.platformDispatcher as RasterTestDispatcher;
    final frame = dispatcher.frameNumber;
    final barrier = RasterCompletionBarrier();
    try {
      dispatcher.frameNumber = -1;
      expect(await barrier.waitForCurrentFrame(), isFalse);
    } finally {
      dispatcher.frameNumber = frame;
      barrier.dispose();
    }
  });

  testWidgets('should preserve other frame timing listeners on disposal', (
    tester,
  ) async {
    var reports = 0;
    void otherListener(List<FrameTiming> _) => reports++;
    SchedulerBinding.instance.addTimingsCallback(otherListener);
    addTearDown(
      () => SchedulerBinding.instance.removeTimingsCallback(otherListener),
    );
    final barrier = RasterCompletionBarrier();
    final frame = tester.platformDispatcher.frameData.frameNumber;
    _report(tester, frame);
    expect(await barrier.waitForCurrentFrame(), isTrue);
    barrier.dispose();
    _report(tester, frame);
    expect(reports, 2);
  });
}

void _report(WidgetTester tester, int frameNumber) {
  tester.platformDispatcher.onReportTimings!([
    FrameTiming(
      vsyncStart: 0,
      buildStart: 1,
      buildFinish: 2,
      rasterStart: 3,
      rasterFinish: 4,
      rasterFinishWallTime: 4,
      frameNumber: frameNumber,
    ),
  ]);
}

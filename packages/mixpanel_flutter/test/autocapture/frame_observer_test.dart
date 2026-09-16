import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/scheduler.dart';
import 'package:mixpanel_flutter/src/autocapture/dead_click_detector.dart';

void main() {
  testWidgets('idle and removed observers receive no frame work',
      (tester) async {
    var active = false;
    var calls = 0;
    void observe() => calls++;
    CaptureFrameObserver.add(observe, () => active);
    try {
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(calls, 0);
      active = true;
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(calls, 1);
      active = false;
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(calls, 1);
      CaptureFrameObserver.remove(observe);
      active = true;
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(calls, 1);
    } finally {
      CaptureFrameObserver.remove(observe);
    }
  });
  testWidgets('A to B to A installs once per binding and dispatches once',
      (tester) async {
    final a = _FrameBinding();
    final b = _FrameBinding();
    var calls = 0;
    void observe() => calls++;
    CaptureFrameObserver.add(observe, () => true);
    try {
      CaptureFrameObserver.installForBinding(a);
      a.frame();
      expect(calls, 1);
      CaptureFrameObserver.installForBinding(b);
      a.frame();
      expect(calls, 1);
      b.frame();
      expect(calls, 2);
      CaptureFrameObserver.installForBinding(a);
      expect(a.persistent, hasLength(1));
      b.frame();
      a.frame();
      expect(calls, 3);
    } finally {
      CaptureFrameObserver.remove(observe);
      CaptureFrameObserver.installForBinding(tester.binding);
    }
  });
}

// A minimal scheduler surface avoids replacing Flutter's process-wide binding.
class _FrameBinding implements SchedulerBinding {
  final persistent = <FrameCallback>[];
  final postFrame = <FrameCallback>[];
  @override
  void addPersistentFrameCallback(FrameCallback callback) =>
      persistent.add(callback);
  @override
  void addPostFrameCallback(FrameCallback callback,
          {String debugLabel = 'callback'}) =>
      postFrame.add(callback);
  void frame() {
    for (final callback in List<FrameCallback>.of(persistent)) {
      callback(Duration.zero);
    }
    final pending = List<FrameCallback>.of(postFrame);
    postFrame.clear();
    for (final callback in pending) {
      callback(Duration.zero);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

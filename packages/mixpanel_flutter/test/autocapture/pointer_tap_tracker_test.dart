import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/src/autocapture/pointer_tap_tracker.dart';

void main() {
  PointerDownEvent down(
          {int pointer = 1,
          PointerDeviceKind kind = PointerDeviceKind.touch,
          int buttons = kPrimaryButton,
          Duration time = Duration.zero}) =>
      PointerDownEvent(
          pointer: pointer, kind: kind, buttons: buttons, timeStamp: time);
  PointerUpEvent up({int pointer = 1, int micros = 1000, double x = 0}) =>
      PointerUpEvent(
          pointer: pointer,
          timeStamp: Duration(microseconds: micros),
          position: Offset(x, 0));

  for (final micros in [0, 499999, 500000, 500001]) {
    test('tap duration $micros microseconds', () {
      final tracker = PointerTapTracker();
      expect(tracker.down(down(), 10), isTrue);
      expect(tracker.up(up(micros: micros)), micros <= 500000);
      expect(tracker.hasPress, isFalse);
    });
  }
  for (final kind in [
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus
  ]) {
    test('pointer kind $kind', () {
      final tracker = PointerTapTracker();
      final accepted =
          kind == PointerDeviceKind.touch || kind == PointerDeviceKind.mouse;
      expect(tracker.down(down(kind: kind), 10), accepted);
      expect(tracker.up(up()), accepted);
    });
  }
  for (final buttons in [
    kPrimaryButton,
    kSecondaryButton,
    kPrimaryButton | kSecondaryButton
  ]) {
    test('button combination $buttons', () {
      final tracker = PointerTapTracker();
      expect(
          tracker.down(down(buttons: buttons), 10), buttons == kPrimaryButton);
      expect(tracker.up(up()), buttons == kPrimaryButton);
    });
  }
  for (final x in [10.0, 10.01]) {
    test('up position slop boundary $x', () {
      final tracker = PointerTapTracker()..down(down(), 10);
      expect(tracker.up(up(x: x)), x <= 10);
    });
  }
  test('movement out and back never restores a tap', () {
    final tracker = PointerTapTracker()..down(down(), 10);
    tracker.move(const PointerMoveEvent(pointer: 1, position: Offset(11, 0)));
    tracker.move(const PointerMoveEvent(pointer: 1));
    expect(tracker.hasPress, isFalse);
    expect(tracker.up(up()), isFalse);
  });
  test('second pointer invalidates both; next independent tap works', () {
    final tracker = PointerTapTracker()..down(down(), 10);
    expect(tracker.down(down(pointer: 2), 10), isFalse);
    expect(tracker.up(up(pointer: 2)), isFalse);
    expect(tracker.up(up()), isFalse);
    expect(tracker.down(down(), 10), isTrue);
    expect(tracker.up(up()), isTrue);
  });
  test('unsupported pointer down does not interrupt supported press', () {
    final tracker = PointerTapTracker()..down(down(), 10);
    expect(tracker.down(down(pointer: 2, kind: PointerDeviceKind.stylus), 10),
        isFalse);
    expect(tracker.up(up()), isTrue);
  });
  test('cancel and reset reject stale up', () {
    final tracker = PointerTapTracker()..down(down(), 10);
    tracker.cancel(const PointerCancelEvent(pointer: 1));
    expect(tracker.up(up()), isFalse);
    tracker.down(down(), 10);
    tracker.reset();
    expect(tracker.up(up()), isFalse);
    expect(tracker.down(down(), 10), isTrue);
    expect(tracker.up(up()), isTrue);
  });
  test('backwards timestamps and unmatched up reject', () {
    final tracker = PointerTapTracker()
      ..down(down(time: const Duration(seconds: 1)), 10);
    expect(tracker.up(up()), isFalse);
    tracker.down(down(), 10);
    expect(tracker.up(up(pointer: 2)), isFalse);
  });
}

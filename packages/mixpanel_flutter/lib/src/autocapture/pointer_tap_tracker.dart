import 'package:flutter/gestures.dart';

/// Passive pointer recognition; never participates in Flutter's gesture arena.
class PointerTapTracker {
  static const maxDuration = Duration(milliseconds: 500);
  final _pointers = <int>{};
  _Press? _press;
  bool get hasPress => _press != null;

  bool down(PointerDownEvent event, double slop) {
    if (event.kind != PointerDeviceKind.touch &&
        event.kind != PointerDeviceKind.mouse) {
      return false;
    }
    _pointers.add(event.pointer);
    _press = null;
    if (_pointers.length != 1 || event.buttons != kPrimaryButton) return false;
    _press = _Press(event.position, event.timeStamp, slop * slop);
    return true;
  }

  void move(PointerMoveEvent event) {
    final press = _press;
    if (press != null &&
        _pointers.contains(event.pointer) &&
        (event.position - press.origin).distanceSquared > press.slopSquared) {
      _press = null; // Returning inside the slop never restores a rejected tap.
    }
  }

  bool up(PointerUpEvent event) {
    final single = _pointers.length == 1 && _pointers.contains(event.pointer);
    _pointers.remove(event.pointer);
    final press = _press;
    _press = null;
    return single &&
        press != null &&
        event.timeStamp >= press.time &&
        event.timeStamp - press.time <= maxDuration &&
        (event.position - press.origin).distanceSquared <= press.slopSquared;
  }

  void cancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    _press = null;
  }

  void reset() {
    _pointers.clear();
    _press = null;
  }
}

class _Press {
  _Press(this.origin, this.time, this.slopSquared);
  final Offset origin;
  final Duration time;
  final double slopSquared;
}

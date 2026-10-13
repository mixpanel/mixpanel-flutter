import 'package:flutter/widgets.dart';
import 'autocapture_options.dart';
import 'click_event.dart';
import 'dead_click_detector.dart';
import 'pointer_tap_tracker.dart';
import 'rage_click_tracker.dart';
import 'response_snapshot.dart';
import 'target_resolver.dart';

/// Turns pointer events for one enabled instance into click, rage-click and
/// dead-click events. Each detector applies its own options.
class CaptureSession {
  CaptureSession(AutocaptureOptions options,
      {required Element root,
      required ResponseSnapshot? Function() capture,
      required void Function(String name, ClickEvent event) emit})
      : _root = root,
        _emit = emit,
        _clickEnabled = options.clickOptions.enabled,
        _rage = RageClickTracker(options.rageClickOptions),
        _dead = DeadClickDetector(options.deadClickOptions, capture: capture);

  final Element _root;
  // Must invoke the transport synchronously, so a later identify cannot
  // relabel an event.
  final void Function(String name, ClickEvent event) _emit;
  final bool _clickEnabled;
  final _taps = PointerTapTracker();
  final _resolver = TargetResolver();
  final RageClickTracker _rage;
  final DeadClickDetector _dead;
  _Press? _press;

  void down(PointerDownEvent event, double slop) {
    _press = null;
    if (!_taps.down(event, slop)) return;
    final target = _resolver.resolve(_root, event);
    if (target == null) return;
    // Capture before ordinary tap handlers; raw pointer handlers may run earlier.
    _press = _Press(target, _dead.baselineFor(target));
  }

  void move(PointerMoveEvent event) {
    _taps.move(event);
    if (!_taps.hasPress) _press = null;
  }

  void cancel(PointerCancelEvent event) {
    _taps.cancel(event);
    _press = null;
  }

  void up(PointerUpEvent event) {
    final accepted = _taps.up(event);
    final press = _press;
    _press = null;
    if (!accepted || press == null || !press.target.element.mounted) return;
    final old = press.target.event;
    final click = ClickEvent(
        x: event.position.dx,
        y: event.position.dy,
        elementId: old.elementId,
        tagName: old.tagName,
        role: old.role,
        elements: old.elements);
    if (_clickEnabled) _emit(r'$mp_click', click);
    if (_rage.record(click.x, click.y, event.timeStamp)) {
      _emit(r'$mp_rage_click', click);
    }
    _dead.start(press.baseline, click, (e) => _emit(r'$mp_dead_click', e));
  }

  /// A scroll, focus or window-metrics change: the UI responded.
  void onResponse() {
    _press?.baseline = null;
    _dead.cancel();
  }

  /// Called by identify() and reset(), so a check armed under the previous
  /// identity never emits under the new one.
  void cancelPendingCheck() => _dead.cancel();

  void reset() {
    _taps.reset();
    _press = null;
    _dead.cancel();
    _rage.reset();
  }
}

/// One accepted press: its target and, when dead detection applies, the
/// snapshot taken at pointer down.
class _Press {
  _Press(this.target, this.baseline);
  final CaptureTarget target;
  ResponseSnapshot? baseline;
}

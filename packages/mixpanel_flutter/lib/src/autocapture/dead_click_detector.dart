import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'click_event.dart';
import 'response_snapshot.dart';

/// One pending check. Unsupported snapshots suppress events, never imply dead.
class DeadClickDetector {
  DeadClickDetector({required this.capture, required this.onDead});
  final ResponseSnapshot? Function() capture;
  final void Function(ClickEvent) onDead;
  ResponseSnapshot? _baseline;
  ClickEvent? _event;
  Timer? _timer;
  int _generation = 0;
  bool get observing => _baseline != null;

  void begin(ResponseSnapshot? baseline) {
    cancel();
    _baseline = baseline;
  }

  void arm(ClickEvent event, int timeoutMs) {
    if (_baseline == null) return;
    _event = event;
    final expected = _generation;
    _timer = Timer(Duration(milliseconds: timeoutMs), () {
      if (expected != _generation) return;
      // Let a response already scheduled for this frame finish building first.
      if (SchedulerBinding.instance.hasScheduledFrame) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (expected == _generation) _finish();
        });
      } else {
        _finish();
      }
    });
  }

  /// Called after produced frames, not by a polling/render loop.
  void sample() {
    final baseline = _baseline;
    if (baseline == null) return;
    final current = capture();
    if (current == null || baseline.differsFrom(current)) cancel();
  }

  void _finish() {
    sample();
    final event = _event;
    final unchanged = _baseline != null;
    cancel();
    if (unchanged && event != null) onDead(event);
  }

  void cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _baseline = null;
    _event = null;
  }
}

/// One dispatcher for the binding lifetime, with removable widget listeners.
/// It never retains disposed widget callbacks and never schedules new frames.
class CaptureFrameObserver {
  static final Set<void Function()> _listeners = {};
  static bool _installed = false;
  static void add(void Function() callback) {
    _listeners.add(callback);
    if (_installed) return;
    _installed = true;
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      if (_listeners.isEmpty) return;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        for (final listener in List<void Function()>.of(_listeners)) {
          if (_listeners.contains(listener)) listener();
        }
      });
    });
  }

  static void remove(void Function() callback) => _listeners.remove(callback);
}

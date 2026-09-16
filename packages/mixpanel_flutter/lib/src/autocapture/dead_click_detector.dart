import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';
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
    sampleSnapshot(capture());
  }

  /// Reuse the frame snapshot when the old candidate and a new press overlap.
  void sampleSnapshot(ResponseSnapshot? current) {
    final baseline = _baseline;
    if (baseline == null) return;
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
  static final Map<void Function(), bool Function()> _listeners = {};
  static SchedulerBinding? _binding;
  // Weak keys avoid retaining replaced test bindings. A -> B -> A must not
  // install a second persistent callback on A.
  static final Expando<bool> _installed =
      Expando<bool>('capture frame observer');
  static void add(void Function() callback, bool Function() isObserving) {
    _listeners[callback] = isObserving;
    installForBinding(SchedulerBinding.instance);
  }

  @visibleForTesting
  static void installForBinding(SchedulerBinding binding) {
    _binding = binding;
    if (_installed[binding] == true) return;
    _installed[binding] = true;
    binding.addPersistentFrameCallback((_) {
      if (!identical(_binding, binding) ||
          !_listeners.values.any((isObserving) => isObserving())) {
        return;
      }
      binding.addPostFrameCallback((_) {
        if (!identical(_binding, binding)) return;
        // A copy permits listeners to detach during delivery. No copy or
        // post-frame callback is allocated when every listener is idle.
        for (final listener in List<void Function()>.of(_listeners.keys)) {
          if (_listeners[listener]?.call() ?? false) listener();
        }
      });
    });
  }

  static void remove(void Function() callback) => _listeners.remove(callback);
}

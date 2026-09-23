import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';
import 'click_event.dart';
import 'response_snapshot.dart';
import 'detection_limits.dart';

/// One pending check. Unsupported snapshots suppress events, never imply dead.
class DeadClickDetector {
  DeadClickDetector({required this.capture, this.onDead});
  final ResponseSnapshot? Function() capture;
  final void Function(ClickEvent)? onDead;
  _PendingDeadClick? _pending;
  bool get observing => _pending != null;

  void begin(ResponseSnapshot? baseline) {
    cancel();
    if (baseline != null) _pending = _PendingDeadClick(baseline);
  }

  void arm(ClickEvent event, Duration timeout,
      {bool Function()? isValid, void Function(ClickEvent)? onDetected}) {
    assert(validTimeWindow(timeout));
    final pending = _pending;
    if (pending == null) return;
    pending.event = event;
    pending.isValid = isValid;
    pending.onDetected = onDetected ?? onDead;
    pending.timer?.cancel();
    pending.timer = Timer(normalizeTimeWindow(timeout), () {
      if (!identical(_pending, pending)) return;
      // Let a response already scheduled for this frame finish building first.
      if (SchedulerBinding.instance.hasScheduledFrame) {
        SchedulerBinding.instance.addPostFrameCallback((_) => _finish(pending));
      } else {
        _finish(pending);
      }
    });
  }

  /// Called after produced frames, not by a polling/render loop.
  void sample() {
    if (_pending == null) return;
    sampleSnapshot(capture());
  }

  /// Reuse the frame snapshot when the old candidate and a new press overlap.
  void sampleSnapshot(ResponseSnapshot? current) {
    final pending = _pending;
    if (pending == null) return;
    if (!(pending.isValid?.call() ?? true) ||
        current == null ||
        pending.baseline.differsFrom(current)) {
      cancel();
    }
  }

  void _finish(_PendingDeadClick pending) {
    if (!identical(_pending, pending)) return;
    sample();
    if (!identical(_pending, pending)) return;
    cancel();
    final event = pending.event;
    if (event != null) pending.onDetected?.call(event);
  }

  void cancel() {
    _pending?.timer?.cancel();
    _pending = null;
  }
}

/// Dropping this object cancels the whole candidate, including deferred frames.
class _PendingDeadClick {
  _PendingDeadClick(this.baseline);
  final ResponseSnapshot baseline;
  ClickEvent? event;
  Timer? timer;
  bool Function()? isValid;
  void Function(ClickEvent)? onDetected;
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

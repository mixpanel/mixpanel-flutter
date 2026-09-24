import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'click_event.dart';
import 'response_snapshot.dart';
import 'detection_limits.dart';

/// One pending check. Unsupported snapshots suppress events, never imply dead.
class DeadClickDetector {
  DeadClickDetector({required this.capture});
  final ResponseSnapshot? Function() capture;
  _PendingDeadClick? _pending;
  bool get observing => _pending != null;

  void start(
      {required ResponseSnapshot? baseline,
      required ClickEvent event,
      required Duration timeout,
      required void Function(ClickEvent) onDetected,
      bool Function()? isValid}) {
    assert(validTimeWindow(timeout));
    cancel();
    if (baseline == null) return;
    final pending = _PendingDeadClick(baseline, event, onDetected, isValid);
    _pending = pending;
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
        pending.baseline.compare(current) != ResponseChange.unchanged) {
      cancel();
    }
  }

  void _finish(_PendingDeadClick pending) {
    if (!identical(_pending, pending)) return;
    sample();
    if (!identical(_pending, pending)) return;
    cancel();
    pending.onDetected(pending.event);
  }

  void cancel() {
    _pending?.timer?.cancel();
    _pending = null;
  }
}

/// Dropping this object cancels the whole candidate, including deferred frames.
class _PendingDeadClick {
  _PendingDeadClick(this.baseline, this.event, this.onDetected, this.isValid);
  final ResponseSnapshot baseline;
  final ClickEvent event;
  Timer? timer;
  final bool Function()? isValid;
  final void Function(ClickEvent) onDetected;
}

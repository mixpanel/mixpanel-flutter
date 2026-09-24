import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'click_event.dart';
import 'response_snapshot.dart';
import 'detection_limits.dart';

/// One pending check: compare the baseline once at the deadline.
/// Unsupported snapshots suppress events, never imply dead.
class DeadClickDetector {
  DeadClickDetector({required this.capture});
  final ResponseSnapshot? Function() capture;
  Timer? _timer;

  void start(
      {required ResponseSnapshot baseline,
      required ClickEvent event,
      required Duration timeout,
      required void Function(ClickEvent) onDetected}) {
    assert(validTimeWindow(timeout));
    cancel();
    late final Timer timer;
    void finish() {
      if (!identical(_timer, timer)) return;
      _timer = null;
      final current = capture();
      if (current != null && !baseline.differsFrom(current)) {
        onDetected(event);
      }
    }

    timer = Timer(normalizeTimeWindow(timeout), () {
      // Let a response already scheduled for this frame finish building first.
      if (SchedulerBinding.instance.hasScheduledFrame) {
        SchedulerBinding.instance.addPostFrameCallback((_) => finish());
      } else {
        finish();
      }
    });
    _timer = timer;
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'autocapture_options.dart';
import 'click_event.dart';
import 'response_snapshot.dart';
import 'target_resolver.dart';
import 'detection_limits.dart';

/// One pending check: compare the baseline once at the deadline.
/// Unsupported snapshots suppress events, never imply dead.
class DeadClickDetector {
  DeadClickDetector(DeadClickOptions options, {required this.capture})
      : _enabled = options.enabled,
        _timeout = normalizeTimeWindow(options.timeWindow) {
    assert(validTimeWindow(options.timeWindow));
  }
  final ResponseSnapshot? Function() capture;
  final bool _enabled;
  final Duration _timeout;
  Timer? _timer;

  /// Captured at pointer down, before the target's tap handler runs. Null
  /// when detection is disabled or the target cannot be dead.
  ResponseSnapshot? baselineFor(CaptureTarget target) =>
      _enabled && target.deadEligible ? capture() : null;

  /// Every accepted tap replaces the pending check, even without a baseline.
  void start(ResponseSnapshot? baseline, ClickEvent event,
      void Function(ClickEvent) onDetected) {
    cancel();
    if (baseline == null) return;
    late final Timer timer;
    void finish() {
      if (!identical(_timer, timer)) return;
      _timer = null;
      final current = capture();
      if (current != null && !baseline.differsFrom(current)) {
        onDetected(event);
      }
    }

    timer = Timer(_timeout, () {
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

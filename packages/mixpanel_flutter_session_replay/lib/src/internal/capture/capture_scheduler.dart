import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';

import '../logger.dart';

/// Helper class that manages capture timing and rate limiting
///
/// This class tracks timing state and provides simple yes/no answers
/// about whether a capture should happen. It has no dependencies on
/// widgets, coordinators, or event recording - it's purely timing logic.
class CaptureScheduler {
  /// Minimum interval between captures (default: 500ms)
  final Duration minInterval;

  /// Logger instance
  final MixpanelLogger _logger;

  /// Timestamp of last capture completion
  DateTime? _lastCaptureTime;

  /// Flag to track if a capture is currently in progress
  bool _isCaptureInProgress = false;

  /// Timer for debouncing capture requests
  Timer? _debounceTimer;

  CaptureScheduler({
    this.minInterval = const Duration(milliseconds: 500),
    required MixpanelLogger logger,
  }) : _logger = logger;

  /// Check if enough time has passed since last capture completed
  ///
  /// Returns false if:
  /// - A capture is already in progress
  /// - Less than 500ms has elapsed since last capture completed
  bool canCapture() {
    // Can't capture if one is already in progress
    if (_isCaptureInProgress) {
      _logger.debug('Capture in progress, cannot start new one');
      return false;
    }

    // Check if 500ms has passed since last completion
    if (_lastCaptureTime == null) return true;

    final elapsed = clock.now().difference(_lastCaptureTime!);
    return elapsed >= minInterval;
  }

  /// Schedule a capture after the remaining rate limit time
  ///
  /// This method is smart about timer management:
  /// - If a capture is in progress, updates timestamp and returns null (ensures re-capture after completion)
  /// - If a timer is already active, does nothing and returns null
  /// - If enough time has passed, schedules callback to execute immediately (Duration.zero timer)
  /// - Otherwise, schedules the callback to run after the remaining time
  Duration? scheduleAfterRateLimit(VoidCallback callback) {
    // Don't schedule if a capture is already in progress
    // But update _lastCaptureTime so next frame callback will schedule a capture after completion
    if (_isCaptureInProgress) {
      _lastCaptureTime = clock.now();
      _logger.debug(
        'Capture in progress, updating timestamp for pending capture',
      );
      return null;
    }

    // Don't schedule if a timer is already active
    if (_debounceTimer?.isActive ?? false) {
      return null;
    }

    // Calculate remaining time (handles race condition where time passes between canCapture check and this call)
    final elapsed = _lastCaptureTime == null
        ? minInterval
        : clock.now().difference(_lastCaptureTime!);

    final remaining = elapsed >= minInterval
        ? Duration
              .zero // Execute immediately
        : minInterval - elapsed;

    final now = clock.now();
    _logger.debug(
      'Scheduling capture in ${remaining.inMilliseconds}ms at ${now.millisecondsSinceEpoch}',
    );
    _debounceTimer = Timer(remaining, callback);

    return remaining;
  }

  /// Mark that a capture has started
  void markCaptureStarted() {
    final now = clock.now();
    _logger.debug('Capture started at ${now.millisecondsSinceEpoch}');
    _isCaptureInProgress = true;
  }

  /// Mark that a capture has completed (success or failure)
  ///
  /// The 500ms rate limit interval starts from this moment.
  /// This is called whether the capture succeeded or failed to ensure
  /// consistent rate limiting (prevents excessive retries on failure).
  void markCaptureCompleted() {
    final now = clock.now();
    _logger.debug('Capture completed at ${now.millisecondsSinceEpoch}');
    _lastCaptureTime = now;
    _isCaptureInProgress = false;
  }

  /// Dispose resources
  void dispose() {
    _debounceTimer?.cancel();
  }
}

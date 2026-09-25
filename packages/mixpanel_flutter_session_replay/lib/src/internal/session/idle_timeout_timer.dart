import 'dart:async';

/// Simple timer wrapper for session idle timeout.
///
/// Resets on every user activity (captures, interactions).
/// When the timeout fires, the provided [onTimeout] callback is invoked
/// to end the current recording session.
///
/// Not web-specific at the type level — only instantiated on web.
class IdleTimeoutTimer {
  final Duration timeout;
  final void Function() onTimeout;
  Timer? _timer;

  IdleTimeoutTimer({required this.timeout, required this.onTimeout});

  /// Reset the timer. Called on every user activity.
  void reset() => resetWith(timeout);

  /// Arm for an explicit remaining duration rather than the full [timeout].
  ///
  /// Used when resuming a persisted session, whose idle deadline was set
  /// before this page load: re-arming for the full timeout would hand the
  /// session another complete inactivity window.
  void resetWith(Duration remaining) {
    _timer?.cancel();
    if (remaining > Duration.zero) {
      _timer = Timer(remaining, onTimeout);
    }
  }

  /// Start the timer (called when recording begins).
  void start() => reset();

  /// Stop the timer (called when recording stops).
  void stop() {
    _timer?.cancel();
  }

  void dispose() {
    _timer?.cancel();
  }
}

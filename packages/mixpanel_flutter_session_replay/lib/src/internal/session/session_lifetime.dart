import 'dart:async';
import 'package:clock/clock.dart';
import 'idle_timeout_timer.dart';

/// Owns a replay's deadlines and their timers across initialization, activity,
/// background pauses and reloads. Deadlines also use wall-clock checks because
/// browser timers can be frozen while the page is suspended.
class SessionLifetime {
  IdleTimeoutTimer? _idleTimer;
  Duration? _maximumDuration;
  final void Function() _onIdleExpired;
  final void Function() _onMaximumExpired;
  Timer? _maximumTimer;
  DateTime? _idleExpiry;
  DateTime? _maximumExpiry;
  DateTime? _backgroundExpiry;

  SessionLifetime({
    IdleTimeoutTimer? idleTimer,
    Duration? maximumDuration,
    required void Function() onIdleExpired,
    required void Function() onMaximumExpired,
  }) : _idleTimer = idleTimer,
       _maximumDuration = maximumDuration,
       _onIdleExpired = onIdleExpired,
       _onMaximumExpired = onMaximumExpired;

  Duration? get maximumDuration => _maximumDuration;
  DateTime? get maximumExpiry => _maximumExpiry;
  DateTime? get backgroundExpiry => _backgroundExpiry;
  bool get hasMaximumTimer => _maximumTimer?.isActive ?? false;
  bool get needsIdleWindow => _idleTimer != null && _idleExpiry == null;
  bool get isIdleExpired => expired(_idleExpiry);
  bool get isMaximumExpired => expired(_maximumExpiry);
  bool get isBackgroundExpired => expired(_backgroundExpiry);

  static bool expired(DateTime? deadline) =>
      deadline != null && !clock.now().isBefore(deadline);

  /// Storage requires an idle deadline even when activity idle is disabled.
  DateTime? get persistedIdleExpiry =>
      _idleExpiry ??
      (_idleTimer == null
          ? _maximumExpiry
          : clock.now().add(_idleTimer!.timeout));

  void begin(DateTime startTime) {
    _maximumExpiry = _maximumDuration == null
        ? null
        : startTime.add(_maximumDuration!);
    _armMaximumTimer();
  }

  void recordActivity({DateTime? deadline}) {
    final timer = _idleTimer;
    if (timer == null) return;
    final now = clock.now();
    _idleExpiry = deadline ?? now.add(timer.timeout);
    final remaining = _idleExpiry!.difference(now);
    timer.resetWith(remaining.isNegative ? Duration.zero : remaining);
  }

  void restoreIdleWindow(DateTime? storedDeadline) {
    final timeout = _idleTimer?.timeout;
    final localDeadline = timeout == null ? null : clock.now().add(timeout);
    recordActivity(
      deadline:
          storedDeadline != null &&
              localDeadline != null &&
              storedDeadline.isBefore(localDeadline)
          ? storedDeadline
          : localDeadline,
    );
  }

  void pause(Duration retention) =>
      _backgroundExpiry = clock.now().add(retention);
  void resumeBackground() => _backgroundExpiry = null;

  /// Rebase remote limits on the original start/last activity, not fetch time.
  /// The caller checks expiry before making the next recording transition.
  void updateLimits({
    Duration? maximumDuration,
    Duration? idleTimeout,
    DateTime? activeSessionStart,
    required bool initializing,
  }) {
    final oldTimeout = _idleTimer?.timeout;
    final lastActivity = _idleExpiry != null && oldTimeout != null
        ? _idleExpiry!.subtract(oldTimeout)
        : clock.now();
    if (maximumDuration != null) _maximumDuration = maximumDuration;
    if (idleTimeout != null) {
      _idleTimer?.dispose();
      _idleTimer = IdleTimeoutTimer(
        timeout: idleTimeout,
        onTimeout: _onIdleExpired,
      );
    }
    if (activeSessionStart == null) return;
    if (maximumDuration != null) begin(activeSessionStart);
    if (idleTimeout != null && !initializing) {
      recordActivity(deadline: lastActivity.add(idleTimeout));
    }
  }

  void _armMaximumTimer() {
    _maximumTimer?.cancel();
    final expiry = _maximumExpiry;
    if (expiry == null) return;
    final remaining = expiry.difference(clock.now());
    // This remains armed while metadata is being persisted or replay is paused.
    _maximumTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      _onMaximumExpired,
    );
  }

  void stop() {
    _idleTimer?.stop();
    _maximumTimer?.cancel();
    _maximumTimer = null;
    _idleExpiry = null;
    _maximumExpiry = null;
    _backgroundExpiry = null;
  }

  void dispose() {
    stop();
    _idleTimer?.dispose();
  }
}

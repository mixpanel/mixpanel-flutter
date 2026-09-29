import 'dart:async';
import 'package:clock/clock.dart';
import 'idle_timeout_timer.dart';
import 'recording_limits.dart';

/// A replay deadline that ends the recording when it passes.
enum ExpiredDeadline { maximum, idle }

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

  /// Without [limits] (native) nothing ever expires.
  SessionLifetime({
    RecordingDurationLimits? limits,
    required void Function() onIdleExpired,
    required void Function() onMaximumExpired,
  }) : _maximumDuration = limits?.maximum,
       _onIdleExpired = onIdleExpired,
       _onMaximumExpired = onMaximumExpired {
    final idle = limits?.idle;
    if (idle != null && idle > Duration.zero) {
      _idleTimer = IdleTimeoutTimer(timeout: idle, onTimeout: onIdleExpired);
    }
  }

  /// Whether this replay has duration limits at all. Remote duration config
  /// applies only then.
  bool get hasLimits => _maximumDuration != null;

  Duration? get maximumDuration => _maximumDuration;
  DateTime? get maximumExpiry => _maximumExpiry;
  bool get hasMaximumTimer => _maximumTimer?.isActive ?? false;
  bool get needsIdleWindow => _idleTimer != null && _idleExpiry == null;
  bool get isIdleExpired => expired(_idleExpiry);
  bool get isMaximumExpired => expired(_maximumExpiry);
  bool get isBackgroundExpired => expired(_backgroundExpiry);

  /// The deadline that has passed by wall clock, if any. The maximum wins
  /// when both have. [includeIdle] false checks only the maximum.
  ExpiredDeadline? expiredDeadline({bool includeIdle = true}) {
    if (isMaximumExpired) return ExpiredDeadline.maximum;
    if (includeIdle && isIdleExpired) return ExpiredDeadline.idle;
    return null;
  }

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

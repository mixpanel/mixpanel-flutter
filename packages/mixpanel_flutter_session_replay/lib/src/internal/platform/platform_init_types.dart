import '../../models/session.dart';
import '../../models/configuration.dart';
import '../screenshot_capturer.dart';
import '../storage/event_queue_interface.dart';

/// The current platform cannot provide a capability required to record
/// without compromising application responsiveness or security.
class PlatformCapabilityException implements Exception {
  final String message;

  const PlatformCapabilityException(this.message);

  @override
  String toString() => message;
}

/// Components produced by platform-specific initialization.
class PlatformInitResult {
  final EventQueue queue;
  final ScreenshotCapturer screenshotCapturer;
  final bool wifiOnly;
  final Duration? idleTimeout;
  final Duration? maxSessionDuration;
  final Session? resumableSession;

  /// Persisted idle deadline for [resumableSession], when one was stored.
  final DateTime? resumableIdleExpiry;
  final Future<void> Function(
    String sessionId,
    int idleExpiresMs,
    int maxExpiresMs,
  )?
  persistIdleExpiry;

  /// Configured behavior when the app or page leaves the foreground.
  final ReplayBackgroundBehavior backgroundBehavior;

  const PlatformInitResult({
    required this.queue,
    required this.screenshotCapturer,
    required this.wifiOnly,
    this.idleTimeout,
    this.maxSessionDuration,
    this.resumableSession,
    this.resumableIdleExpiry,
    this.persistIdleExpiry,
    required this.backgroundBehavior,
  });
}

import '../../models/session.dart';
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
  final Future<void> Function(
    String sessionId,
    int idleExpiresMs,
    int maxExpiresMs,
  )?
  persistIdleExpiry;

  /// Whether leaving the foreground ends the recording session.
  ///
  /// True on native, matching mixpanel-android/ios: backgrounding may precede
  /// process suspension, so the session is a real boundary and the next
  /// foreground re-rolls sampling into a new session.
  ///
  /// False on web, matching Mixpanel JS: `visibilitychange` fires for a tab
  /// switch, an OAuth or payment popup, or an alt-tab, none of which are
  /// session boundaries. The session is staged for resume instead, so the
  /// same `$mp_replay_id` continues and sampling is not re-rolled. Only the
  /// idle timeout and max session duration end a web session.
  final bool backgroundEndsSession;

  const PlatformInitResult({
    required this.queue,
    required this.screenshotCapturer,
    required this.wifiOnly,
    this.idleTimeout,
    this.maxSessionDuration,
    this.resumableSession,
    this.persistIdleExpiry,
    this.backgroundEndsSession = true,
  });
}

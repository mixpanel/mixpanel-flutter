import '../session/resumable_session.dart';
import '../../models/configuration.dart';
import '../screenshot_capturer.dart';
import '../storage/event_queue_interface.dart';
import 'gzip_compressor.dart';

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

  /// Upload payload compressor, owned by this SDK instance.
  final GzipCompressor gzipCompressor;
  final bool wifiOnly;
  final Duration? idleTimeout;
  final Duration? maxSessionDuration;
  final ResumableSession? resumableSession;

  final Future<void> Function(
    String sessionId,
    int idleExpiresMs,
    int maxExpiresMs,
    int? backgroundExpiresMs,
  )?
  persistIdleExpiry;

  /// Configured behavior when the app or page leaves the foreground.
  final ReplayBackgroundBehavior backgroundBehavior;

  const PlatformInitResult({
    required this.queue,
    required this.screenshotCapturer,
    required this.gzipCompressor,
    required this.wifiOnly,
    this.idleTimeout,
    this.maxSessionDuration,
    this.resumableSession,
    this.persistIdleExpiry,
    required this.backgroundBehavior,
  });

  /// Releases every platform resource this result holds.
  ///
  /// Once the coordinator owns these components it disposes them itself.
  /// This is for the window in between, when SDK initialization fails after
  /// platform initialization succeeded.
  Future<void> dispose() async {
    await screenshotCapturer.dispose();
    gzipCompressor.dispose();
    await queue.dispose();
  }
}

import '../session/recording_limits.dart';
import '../session/session_persistence.dart';
import '../../models/configuration.dart';
import '../debug_mask_overlay.dart';
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

  /// Web replays' duration limits; null on native, which has none.
  final RecordingDurationLimits? durationLimits;

  /// Carries replays across page loads on web; a no-op elsewhere.
  final SessionPersistence sessionPersistence;

  /// Configured behavior when the app or page leaves the foreground.
  final ReplayBackgroundBehavior backgroundBehavior;

  /// Draws the debug mask overlay where [screenshotCapturer] cannot see it.
  final DebugMaskOverlayFactory debugMaskOverlayFactory;

  const PlatformInitResult({
    required this.queue,
    required this.screenshotCapturer,
    required this.gzipCompressor,
    required this.wifiOnly,
    this.durationLimits,
    required this.sessionPersistence,
    required this.backgroundBehavior,
    required this.debugMaskOverlayFactory,
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

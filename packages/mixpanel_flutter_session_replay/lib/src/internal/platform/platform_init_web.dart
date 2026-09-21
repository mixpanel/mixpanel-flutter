export 'platform_init_types.dart';

import '../storage/event_queue_interface.dart';
import '../storage/event_queue_factory_web.dart';
import '../storage/indexed_db_event_queue.dart';
import '../storage/memory_event_queue.dart';
import '../logger.dart';
import '../wireframe/wireframe_emitter.dart';
import '../../models/masking_directive.dart';
import '../session/web_session_resume.dart';
import '../screenshot_capturer.dart';
import 'gzip_compress.dart';
import 'platform_init_types.dart';
import 'web_image_compressor.dart';

const _webStorageRetention = Duration(days: 5);

Future<PlatformInitResult> platformInit({
  required String token,
  required int storageQuotaMB,
  required MaskingDirective directive,
  required bool debugOverlayEnabled,
  required bool mobileWifiOnly,
  required Duration webIdleTimeout,
  required Duration webMaxSessionDuration,
  WireframeEmitter? wireframeEmitter,
  required bool useAccessibilityLabelFallback,
  required MixpanelLogger logger,
  EventQueue? eventQueue,
}) async {
  if (!isGzipSupported) {
    throw const PlatformCapabilityException(
      'Browser CompressionStream support is required for Session Replay',
    );
  }

  try {
    await initializeGzipCompression();
  } catch (error) {
    throw PlatformCapabilityException(error.toString());
  }

  EventQueue queue =
      eventQueue ??
      createWebEventQueue(
        token: token,
        quotaMB: storageQuotaMB,
        logger: logger,
      );
  try {
    await queue.initialize();
  } catch (error) {
    if (eventQueue != null) rethrow;
    logger.warning(
      'IndexedDB unavailable; replay will use page-lifetime memory storage: '
      '$error',
    );
    queue = MemoryEventQueue(quotaMB: storageQuotaMB, logger: logger);
    await queue.initialize();
  }

  if (queue is IndexedDbEventQueue) {
    try {
      final cleanup = await queue.pruneExpiredData(
        DateTime.now().subtract(_webStorageRetention),
      );
      if (cleanup.removedEvents > 0 || cleanup.removedSessions > 0) {
        logger.info(
          'Removed ${cleanup.removedEvents} expired replay events and '
          '${cleanup.removedSessions} abandoned sessions',
        );
      }
    } catch (error) {
      // Retention is best-effort. A cleanup failure must not discard the
      // otherwise usable persistent queue or prevent recording.
      logger.warning('Failed to prune expired web replay data: $error');
    }
  }

  // Check for resumable session before clearing data
  final resumeInfo = await checkWebSessionResume(
    queue: queue,
    idleTimeout: webIdleTimeout,
    maxSessionDuration: webMaxSessionDuration,
    logger: logger,
  );

  if (resumeInfo != null) {
    logger.info('Found resumable session: ${resumeInfo.session.id}');
  } else {
    // A session that cannot be resumed may still have events waiting to upload
    // from an earlier page load. Do not clear the token-wide queue here: the
    // uploader owns deletion after a successful request, while a later storage
    // retention policy can garbage-collect genuinely abandoned data.
    logger.debug('No resumable session; preserving queued upload backlog');
  }

  final imageCompressor = WebImageCompressor(logger: logger);
  try {
    await imageCompressor.initialize();
  } catch (error) {
    await queue.dispose();
    throw PlatformCapabilityException(error.toString());
  }

  final screenshotCapturer = ScreenshotCapturer(
    directive: directive,
    logger: logger,
    debugOverlayEnabled: debugOverlayEnabled,
    compressor: imageCompressor,
    wireframeEmitter: wireframeEmitter,
    useAccessibilityLabelFallback: useAccessibilityLabelFallback,
  );

  // Create persist callback for debounced idle expiry writes
  Future<void> Function(String, int, int)? persistIdleExpiry;
  persistIdleExpiry =
      (String sessionId, int idleExpiresMs, int maxExpiresMs) async {
        try {
          await updateWebSessionExpiry(
            queue: queue,
            sessionId: sessionId,
            idleExpiresMs: idleExpiresMs,
            maxExpiresMs: maxExpiresMs,
            logger: logger,
          );
        } catch (e) {
          logger.error('Failed to persist session expiry: $e');
        }
      };

  return PlatformInitResult(
    queue: queue,
    screenshotCapturer: screenshotCapturer,
    wifiOnly: false,
    idleTimeout: webIdleTimeout,
    maxSessionDuration: webMaxSessionDuration,
    resumableSession: resumeInfo?.session,
    persistIdleExpiry: persistIdleExpiry,
    backgroundEndsSession: false,
  );
}

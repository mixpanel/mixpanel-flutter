export 'platform_init_types.dart';

import 'package:flutter/foundation.dart' show kIsWasm;

import '../capture/rendered_surface_frame_acquirer.dart';
import '../debug_mask_overlay.dart';
import '../storage/event_queue_interface.dart';
import '../storage/event_queue_factory_web.dart';
import '../storage/indexed_db_event_queue.dart';
import '../storage/memory_event_queue.dart';
import '../logger.dart';
import '../wireframe/wireframe_emitter.dart';
import '../../models/masking_directive.dart';
import '../../models/configuration.dart';
import '../session/recording_limits.dart';
import '../session/replay_lifecycle_policy.dart';
import '../session/resumable_session.dart';
import '../session/session_persistence.dart';
import '../session/web_session_resume.dart';
import '../screenshot_capturer.dart';
import 'gzip_compressor.dart';
import 'platform_init_types.dart';
import 'web_rendered_surface_capture.dart';

const _webStorageRetention = Duration(days: 5);

Future<PlatformInitResult> platformInit({
  required String token,
  required int storageQuotaMB,
  required MaskingDirective directive,
  required bool debugOverlayEnabled,
  required PlatformOptions platformOptions,
  WireframeEmitter? wireframeEmitter,
  required bool useAccessibilityLabelFallback,
  required MixpanelLogger logger,
  EventQueue? eventQueue,
}) async {
  final web = platformOptions.web;
  final gzip = createGzipCompressor();
  if (!gzip.isSupported) {
    throw const PlatformCapabilityException(
      'Browser CompressionStream support is required for Session Replay',
    );
  }

  try {
    await gzip.initialize();
  } catch (error) {
    gzip.dispose();
    throw PlatformCapabilityException(error.toString());
  }

  // Everything created from here on is released again when a later step
  // fails, so a failed initialization never leaks a worker, its Blob URL, or
  // a database connection into the page.
  EventQueue? queue;
  WebRenderedSurfaceCapture? surfaceCapture;
  try {
    queue = await _openQueue(
      injected: eventQueue,
      token: token,
      quotaMB: storageQuotaMB,
      logger: logger,
    );
    final SessionPersistence sessionPersistence;
    if (queue case final IndexedDbEventQueue persistent) {
      await _pruneExpiredData(persistent, logger);
      sessionPersistence = StoredSessionPersistence(
        resumable: await _checkSessionResume(
          persistent,
          maxSessionDuration: web.maxSessionDuration,
          logger: logger,
        ),
        logger: logger,
        write: _deadlineWriter(persistent, logger),
      );
    } else {
      // Page-lifetime memory storage cannot carry a replay across page loads.
      sessionPersistence = SessionPersistence.none();
    }

    surfaceCapture = WebRenderedSurfaceCapture(logger: logger);
    try {
      await surfaceCapture.initialize();
    } catch (error) {
      throw PlatformCapabilityException(error.toString());
    }

    final screenshotCapturer = ScreenshotCapturer(
      directive: directive,
      logger: logger,
      debugOverlayEnabled: debugOverlayEnabled,
      // Wasm builds render with skwasm, whose canvas can lag Dart frames.
      frameAcquirer: RenderedSurfaceFrameAcquirer(
        surfaceCapture,
        awaitFreshFrame: kIsWasm,
      ),
      wireframeEmitter: wireframeEmitter,
      useAccessibilityLabelFallback: useAccessibilityLabelFallback,
    );

    return PlatformInitResult(
      queue: queue,
      screenshotCapturer: screenshotCapturer,
      gzipCompressor: gzip,
      wifiOnly: false,
      durationLimits: RecordingDurationLimits(
        maximum: web.maxSessionDuration,
        idle: web.idleTimeout,
      ),
      sessionPersistence: sessionPersistence,
      lifecyclePolicy: ReplayLifecyclePolicy.recordThroughBackground,
      // Capture reads the presented Flutter canvas, which would include
      // anything painted in-tree.
      debugMaskOverlayFactory: OutOfSurfaceDebugMaskOverlay.new,
    );
  } catch (_) {
    await surfaceCapture?.dispose();
    await queue?.dispose();
    gzip.dispose();
    rethrow;
  }
}

/// Opens the injected queue, or the persistent browser queue with an
/// in-memory fallback when IndexedDB is unavailable.
///
/// An injected queue is owned by the SDK from here on, like the queues this
/// function creates, and is never swapped for the fallback: a caller that
/// supplied one wants that queue or a failure.
Future<EventQueue> _openQueue({
  required EventQueue? injected,
  required String token,
  required int quotaMB,
  required MixpanelLogger logger,
}) async {
  if (injected != null) {
    await injected.initialize();
    return injected;
  }
  final persistent = createWebEventQueue(
    token: token,
    quotaMB: quotaMB,
    logger: logger,
  );
  try {
    await persistent.initialize();
    return persistent;
  } catch (error) {
    logger.warning(
      'IndexedDB unavailable; replay will use page-lifetime memory storage: '
      '$error',
    );
    await persistent.dispose();
    final memory = MemoryEventQueue(quotaMB: quotaMB, logger: logger);
    await memory.initialize();
    return memory;
  }
}

/// Stores replay deadlines in [queue]. Failures are logged, never thrown.
SessionDeadlineWriter _deadlineWriter(
  IndexedDbEventQueue queue,
  MixpanelLogger logger,
) => (sessionId, idleExpiresMs, maxExpiresMs) async {
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

/// Retention is best-effort. A cleanup failure must not discard the
/// otherwise usable persistent queue or prevent recording.
Future<void> _pruneExpiredData(
  IndexedDbEventQueue queue,
  MixpanelLogger logger,
) async {
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
    logger.warning('Failed to prune expired web replay data: $error');
  }
}

/// Resuming is an improvement over starting a new replay, never a
/// requirement: a malformed or unreadable metadata record leaves the SDK
/// recording fresh rather than failing to initialize on every page load.
Future<ResumableSession?> _checkSessionResume(
  IndexedDbEventQueue queue, {
  required Duration maxSessionDuration,
  required MixpanelLogger logger,
}) async {
  try {
    final resumeInfo = await checkWebSessionResume(
      queue: queue,
      maxSessionDuration: maxSessionDuration,
      logger: logger,
    );
    if (resumeInfo != null) {
      logger.info('Found resumable session: ${resumeInfo.session.id}');
    } else {
      // A session that cannot be resumed may still have events waiting to
      // upload from an earlier page load. The token-wide queue is not cleared
      // here: the uploader owns deletion after a successful request, and the
      // retention pass above garbage-collects genuinely abandoned data.
      logger.debug('No resumable session; preserving queued upload backlog');
    }
    return resumeInfo;
  } catch (error) {
    logger.warning(
      'Could not check for a resumable session; starting fresh: $error',
    );
    return null;
  }
}

import 'package:clock/clock.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../models/configuration.dart';
import '../models/results.dart';
import '../models/masking_directive.dart';
import '../models/session_event.dart';
import 'masking/mask_detector.dart';
import '../models/session.dart';
import 'wireframe/wireframe_emitter.dart';
import 'logger.dart';
import 'capture/frame_acquirer.dart';
import 'capture/mask_layout_fence.dart';

/// Screenshot capturer with masking and platform-injected acquisition.
///
/// Owns the steps every platform shares: waiting out the frame in flight,
/// pinning replay identity, mask detection, wireframes and the result.
/// Reading, masking and encoding pixels is delegated to the injected
/// [FrameAcquirer].
class ScreenshotCapturer {
  /// Masking directive for privacy rules
  final MaskingDirective directive;

  /// Logger instance
  final MixpanelLogger logger;

  /// Whether debug overlay is enabled (determines if we track unmask bounds)
  final bool debugOverlayEnabled;

  final FrameAcquirer _acquirer;

  /// Optional wireframe emitter. When non-null, wireframes are collected on
  /// the same walk as mask detection and enqueued alongside each screenshot.
  final WireframeEmitter? _wireframeEmitter;

  /// Mirrors `WireframesOptions.useAccessibilityLabelFallback`; only consulted
  /// when [_wireframeEmitter] is non-null.
  final bool _useAccessibilityLabelFallback;

  /// Duration of the most recent mask traversal, exposed for integration
  /// performance validation of the capture pipeline.
  Duration? lastMaskDetectionTime;

  /// Duration of the corresponding post-snapshot privacy validation, or null
  /// when the acquirer did not need one.
  Duration? lastPostSnapshotMaskValidationTime;

  /// The server's verdict on wireframe capture, or null until `/settings`
  /// answers.
  ///
  /// Unlike the other platforms — where remote settings resolve before the
  /// instance is built and the kill switch simply clears `wireframesOptions` —
  /// the emitter here is constructed at SDK init and the settings fetch lands
  /// on first foreground. Recording can be started manually in between, so the
  /// verdict starts unknown and capture is **suppressed until it arrives**:
  /// nothing can be captured, queued, and then flushed before the server has
  /// been asked.
  bool? _wireframesRemotelyEnabled;

  /// Whether wireframes are collected on the next capture: opted in locally and
  /// affirmatively allowed by the server.
  bool get wireframesEnabled =>
      _wireframeEmitter != null && (_wireframesRemotelyEnabled ?? false);

  /// Clears wireframe dedup state at a recording-session boundary.
  ///
  /// Forwarded rather than exposing [_wireframeEmitter] itself: the capturer owns the
  /// emitter, and the coordinator — which knows when a session starts — already holds
  /// the capturer. No-op when wireframes are off. See [WireframeEmitter.resetDedup].
  void resetWireframeDedup() => _wireframeEmitter?.resetDedup();

  /// Marks the wireframe of the most recent accepted frame as the dedup
  /// baseline. See [WireframeEmitter.commitPending].
  void commitWireframeDedup() => _wireframeEmitter?.commitPending();

  /// Records the server's verdict on wireframe capture.
  ///
  /// Called by the coordinator once `/settings` answers — including the
  /// cached-fallback answer a failed fetch produces. Until then wireframes are
  /// suppressed; see [_wireframesRemotelyEnabled]. Screenshots are unaffected
  /// either way: when the verdict is `false` the traversal stops collecting
  /// elements and only the wireframe payload is dropped.
  void applyRemoteWireframeVerdict({required bool isEnabled}) =>
      _wireframesRemotelyEnabled = isEnabled;

  ScreenshotCapturer({
    required this.directive,
    required this.logger,
    required this.debugOverlayEnabled,
    required FrameAcquirer frameAcquirer,
    WireframeEmitter? wireframeEmitter,
    bool useAccessibilityLabelFallback = false,
  }) : _acquirer = frameAcquirer,
       _wireframeEmitter = wireframeEmitter,
       _useAccessibilityLabelFallback = useAccessibilityLabelFallback;

  /// Capture screenshot with masking.
  ///
  /// Parameters:
  /// - [boundary]: The render boundary to capture
  /// - [boundaryElement]: The root element used for wireframe traversal
  /// - [maskTypes]: Set of view types to auto-mask (overrides directive if provided)
  /// - [getCurrentSession], [getDistinctId]: read at the frame to pin its identity
  /// - [isCancelled]: polled after every await before pixels are acquired and
  ///   before they are encoded, so a frame whose recording stopped or paused
  ///   while it waited is never captured
  /// Returns CaptureResult with compressed image data or error
  Future<CaptureResult> capture(
    RenderRepaintBoundary boundary, {
    required Session Function() getCurrentSession,
    required String Function() getDistinctId,
    required Element boundaryElement,
    Set<AutoMaskedView>? maskTypes,
    bool Function()? isCancelled,
  }) async {
    final captureStart = clock.now();
    bool cancelled() => isCancelled?.call() ?? false;
    try {
      if (!_acquirer.isAvailable) {
        return const CaptureFailure(
          CaptureError.compressionFailed,
          'Image compression is unavailable',
        );
      }

      final captureDirective = maskTypes != null
          ? MaskingDirective(autoMaskTypes: maskTypes)
          : directive;

      // Create mask detector with specified mask types or use default directive
      final maskDetector = MaskDetector(
        directive: captureDirective,
        trackUnmaskBounds: debugOverlayEnabled,
        collectWireframes: wireframesEnabled,
        useAccessibilityLabelFallback: _useAccessibilityLabelFallback,
      );

      // Mask detection and snapshot initiation must observe the same
      // completed Flutter paint, so wait out any frame still in flight.
      await _awaitPaintedFrame();
      if (cancelled()) return cancelledCaptureFailure;
      final preparing = _acquirer.prepare(boundary.size);
      final sourceStatus = preparing is Future<FrameSourceStatus>
          ? await preparing
          : preparing;
      if (cancelled()) return cancelledCaptureFailure;
      switch (sourceStatus) {
        case FrameSourceStatus.ready:
          break;
        case FrameSourceStatus.readyAfterPlatformFrame:
          // Re-establish the same-painted-frame invariant before reading
          // mask coordinates.
          await _awaitPaintedFrame();
          if (cancelled()) return cancelledCaptureFailure;
        case FrameSourceStatus.unavailable:
          return const CaptureFailure(
            CaptureError.renderBoundaryNotFound,
            'Rendered surface is not available for capture',
          );
      }

      // Pinned here because every step below yields, letting identity move.
      final sessionId = getCurrentSession().id;
      final distinctId = getDistinctId();

      // Detect masks after paint is complete
      final maskDetectionStart = clock.now();
      MaskDetectionResult maskResult;
      try {
        maskResult = maskDetector.detectMaskRegions(
          boundary,
          boundaryElement: boundaryElement,
        );
      } catch (e) {
        return CaptureFailure(
          CaptureError.maskDetectionFailed,
          'Failed to detect mask regions: $e',
        );
      }
      final maskRegions = maskResult.maskRegions;
      final maskDetectionTime = clock.now().difference(maskDetectionStart);
      lastMaskDetectionTime = maskDetectionTime;
      logger.debug(
        'Mask detection: ${maskDetectionTime.inMilliseconds}ms (found ${maskRegions.length} masks)',
      );

      // Skip capture when visual state would cause mask coordinate mismatch
      // (route transitions show overlapping unmasked content, overscroll stretch
      // shifts content via paint-only transform not reflected in getTransformTo)
      if (maskResult.shouldSkipCapture) {
        logger.debug(
          'Skipping capture: visual state would cause mask mismatch',
        );
        return CaptureFailure(
          CaptureError.maskDetectionFailed,
          'Visual state would cause mask coordinate mismatch',
        );
      }

      final logicalSize = boundary.size;
      final fence = MaskLayoutFence(
        directive: captureDirective,
        trackUnmaskBounds: debugOverlayEnabled,
        boundary: boundary,
        boundaryElement: boundaryElement,
        observed: maskResult,
        observedViewport: logicalSize,
        observedFrameTimeStamp:
            SchedulerBinding.instance.currentSystemFrameTimeStamp,
      );

      // No await between the mask walk and this call: an acquirer that
      // snapshots Flutter's layer tree does so before it first yields.
      final acquisition = await _acquirer.acquire(
        FrameRequest(
          boundary: boundary,
          logicalSize: logicalSize,
          maskRegions: maskRegions,
          fence: fence,
          isCancelled: cancelled,
        ),
      );
      lastPostSnapshotMaskValidationTime = fence.lastCheckTime;

      switch (acquisition) {
        case FrameRejected(:final failure):
          return failure;
        case AcquiredFrame(:final data, :final width, :final height):
          final timestamp = acquisition.capturedAt;
          final wireframePayload = _emitWireframes(
            maskResult: maskResult,
            maskRegions: maskRegions,
            viewport: logicalSize,
            timestamp: timestamp,
            sessionId: sessionId,
          );
          final totalTime = clock.now().difference(captureStart);
          logger.debug(
            'Total capture time: ${totalTime.inMilliseconds}ms '
            '(${width}x$height raster, '
            '${(data.length / 1024).toStringAsFixed(1)}KB)',
          );
          return CaptureSuccess(
            data: data,
            width: logicalSize.width.round(),
            height: logicalSize.height.round(),
            maskCount: maskRegions.length,
            timestamp: timestamp,
            maskRegions: maskRegions,
            wireframes: wireframePayload,
            sessionId: sessionId,
            distinctId: distinctId,
          );
      }
    } catch (e) {
      final totalTime = clock.now().difference(captureStart);
      logger.error('Capture failed after ${totalTime.inMilliseconds}ms: $e');
      return CaptureFailure(
        CaptureError.maskDetectionFailed,
        'Unexpected capture error: $e',
      );
    }
  }

  /// Waits for the frame in flight, if any, so the render tree read next
  /// matches what is on screen.
  ///
  /// When the scheduler is idle and no frame has been requested, the last
  /// painted frame already is the settled screen and there is nothing to wait
  /// for. Awaiting `endOfFrame` in that state would request a frame of its
  /// own, which the persistent frame callback then reports as new content
  /// and the scheduler answers with another capture: a static screen would
  /// be captured indefinitely. Capture must never be what schedules a frame.
  static Future<void> _awaitPaintedFrame() {
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.idle &&
        !scheduler.hasScheduledFrame) {
      return Future<void>.value();
    }
    return scheduler.endOfFrame;
  }

  Future<void> dispose() => _acquirer.dispose();

  WireframePayload? _emitWireframes({
    required MaskDetectionResult maskResult,
    required List<MaskRegionInfo> maskRegions,
    required Size viewport,
    required DateTime timestamp,
    required String? sessionId,
  }) {
    final rawWireframes = maskResult.rawWireframes;
    // Spelled out rather than via [wireframesEnabled] so Dart promotes
    // [_wireframeEmitter] to non-null for the emit call below.
    return (_wireframeEmitter != null &&
            (_wireframesRemotelyEnabled ?? false) &&
            rawWireframes != null)
        ? _wireframeEmitter.emit(
            rawElements: rawWireframes,
            maskRegions: maskRegions,
            viewport: viewport,
            timestamp: timestamp,
            sessionId: sessionId,
          )
        : null;
  }
}

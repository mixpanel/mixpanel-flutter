import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../models/configuration.dart';
import '../models/results.dart';
import '../models/masking_directive.dart';
import '../models/session_event.dart';
import 'masking/mask_detector.dart';
import 'masking/mask_painter.dart';
import '../models/session.dart';
import 'wireframe/wireframe_emitter.dart';
import 'logger.dart';

/// Interface for platform-specific image compression.
///
/// Implementations handle compressing raw RGBA bytes into an encoded
/// format (typically JPEG) using platform-optimized APIs:
/// - Native: MethodChannel to Android/iOS JPEG encoders
/// - Web: OffscreenCanvas.convertToBlob() via Web Worker
abstract class ImageCompressor {
  /// Whether this compressor can still accept work.
  ///
  /// Platform implementations can switch this to false after a permanent
  /// runtime failure so frame capture stops before allocating an RGBA image.
  bool get isAvailable => true;

  /// Whether privacy mask rectangles are painted by the compressor.
  ///
  /// Web performs this inside its image worker to avoid rendering a second
  /// full-size Flutter image on the UI isolate. Native compressors keep the
  /// default and receive pixels already masked by [MaskPainter].
  bool get paintsMasks => false;

  /// Whether this implementation captures the already-rendered platform
  /// surface without first materializing a [ui.Image] in Dart.
  ///
  /// Flutter web uses this path to transfer the browser canvas to a worker as
  /// an ImageBitmap. Native implementations keep the default RGBA path.
  bool get capturesRenderedSurface => false;

  /// Upper bound applied to the platform-independent capture ratio.
  /// Implementations may lower it when their encoding pipeline competes with
  /// frame rendering on resource-constrained devices.
  double get maximumCapturePixelRatio => 1;

  /// Wait for a directly captured platform surface to become discoverable.
  /// If discovery crosses a browser frame, the caller waits for another
  /// Flutter end-of-frame so it cannot separate mask detection from snapshot
  /// start.
  Future<RenderedSurfaceAvailability> waitUntilRenderedSurfaceAvailable(
    Size logicalSize,
  ) async => RenderedSurfaceAvailability.available;

  /// Waits for a platform presentation opportunity before direct capture.
  ///
  /// A browser canvas can lag Flutter's render tree by one presented frame.
  /// The caller compares mask geometry before and after this barrier and only
  /// snapshots a surface whose privacy coordinates stayed stable.
  Future<void> waitForRenderedSurfacePresentation() async {}

  /// Capture, resize, mask, and encode the current rendered surface.
  ///
  /// [maskRects] are expressed in the requested output raster coordinates.
  /// [validateSnapshot] must be invoked after the source becomes an immutable
  /// snapshot and before any encoding work starts. Implementations may yield a
  /// browser presentation opportunity first to keep the validation walk out of
  /// the snapshot frame; the immutable source must remain local until it
  /// validates.
  /// Implementations must return `null` rather than an unmasked image when the
  /// correct surface cannot be identified or captured.
  Future<Uint8List?> captureRenderedSurface({
    required Size logicalSize,
    required int outputWidth,
    required int outputHeight,
    List<Rect> maskRects = const [],
    bool Function()? validateSnapshot,
  }) async => null;

  /// Compress raw RGBA bytes into an encoded image.
  ///
  /// Returns compressed bytes, or null on failure.
  Future<Uint8List?> compress(
    Uint8List rgbaBytes, {
    required int width,
    required int height,
    List<Rect> maskRects = const [],
  });

  /// Release resources held by the compressor.
  Future<void> dispose();
}

/// Screenshot capturer with masking and platform-injected compression.
///
/// Handles mask detection, image capture, and mask painting. Delegates
/// compression to the injected [ImageCompressor].
class ScreenshotCapturer {
  /// Maximum raster area captured from the rendered web surface.
  ///
  /// 1280x720 is comfortably above normal phone viewports while bounding the
  /// work caused by large browser viewports. Native capture stays at its
  /// existing 1:1 logical resolution.
  static const int maxRasterPixels = 1280 * 720;

  /// Secondary bound for pathological ultra-wide or ultra-tall viewports.
  static const double maxRasterLongEdge = 1920;

  /// Masking directive for privacy rules
  final MaskingDirective directive;

  /// Logger instance
  final MixpanelLogger logger;

  /// Whether debug overlay is enabled (determines if we track unmask bounds)
  final bool debugOverlayEnabled;

  /// Platform-specific image compressor
  final ImageCompressor _compressor;

  /// Whether capture reads the already-rendered platform surface.
  bool get capturesRenderedSurface => _compressor.capturesRenderedSurface;

  /// Optional wireframe emitter. When non-null, wireframes are collected on
  /// the same walk as mask detection and enqueued alongside each screenshot.
  final WireframeEmitter? _wireframeEmitter;

  /// Mirrors `WireframesOptions.useAccessibilityLabelFallback`; only consulted
  /// when [_wireframeEmitter] is non-null.
  final bool _useAccessibilityLabelFallback;

  /// Duration of the most recent mask traversal, exposed for integration
  /// performance validation of the capture pipeline.
  Duration? lastMaskDetectionTime;

  /// Duration of the corresponding post-snapshot privacy validation.
  Duration? lastPostSnapshotMaskValidationTime;

  /// Duration of web's pre-snapshot presentation/stability validation.
  Duration? lastRenderedSurfaceStabilityValidationTime;

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

  /// Records the server's verdict on wireframe capture.
  ///
  /// Called by the coordinator once `/settings` answers — including the
  /// cached-fallback answer a failed fetch produces. Until then wireframes are
  /// suppressed; see [_wireframesRemotelyEnabled]. Screenshots are unaffected
  /// either way: when the verdict is `false` the traversal stops collecting
  /// elements and only the wireframe payload is dropped.
  void applyRemoteWireframeVerdict({required bool isEnabled}) =>
      _wireframesRemotelyEnabled = isEnabled;

  /// Mask painter (reusable across captures)
  final MaskPainter _maskPainter = MaskPainter();

  ScreenshotCapturer({
    required this.directive,
    required this.logger,
    required this.debugOverlayEnabled,
    required ImageCompressor compressor,
    WireframeEmitter? wireframeEmitter,
    bool useAccessibilityLabelFallback = false,
  }) : _compressor = compressor,
       _wireframeEmitter = wireframeEmitter,
       _useAccessibilityLabelFallback = useAccessibilityLabelFallback;

  /// Returns a down-only capture ratio that preserves aspect ratio while
  /// bounding both raster area and the longest encoded edge.
  ///
  /// The exact limiting ratio is used so captures retain as much detail as the
  /// raster budget permits. A power-of-two step would often discard most of
  /// the budget; for example, a nearly square 1200-pixel viewport would fall
  /// all the way to 600 pixels wide.
  static double capturePixelRatioFor(Size logicalSize) {
    final width = logicalSize.width;
    final height = logicalSize.height;
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      return 1;
    }

    final areaRatio = math.sqrt(maxRasterPixels / (width * height));
    final longEdgeRatio = maxRasterLongEdge / math.max(width, height);
    return math.min(1.0, math.min(areaRatio, longEdgeRatio));
  }

  /// Capture screenshot with masking.
  ///
  /// Performs mask detection, image capture, mask painting, then delegates
  /// to the injected [ImageCompressor] for compression.
  ///
  /// Parameters:
  /// - [boundary]: The render boundary to capture
  /// - [boundaryElement]: The root element used for wireframe traversal
  /// - [maskTypes]: Set of view types to auto-mask (overrides directive if provided)
  /// - [getCurrentSession], [getDistinctId]: read at the frame to pin its identity
  /// Returns CaptureResult with compressed image data or error
  Future<CaptureResult> capture(
    RenderRepaintBoundary boundary, {
    required Session Function() getCurrentSession,
    required String Function() getDistinctId,
    required Element boundaryElement,
    Set<AutoMaskedView>? maskTypes,
  }) async {
    final captureStart = clock.now();
    try {
      if (!_compressor.isAvailable) {
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

      // endOfFrame ensures mask detection and snapshot initiation observe the
      // same completed Flutter paint.
      await SchedulerBinding.instance.endOfFrame;
      if (_compressor.capturesRenderedSurface) {
        final surfaceAvailability = await _compressor
            .waitUntilRenderedSurfaceAvailable(boundary.size);
        if (surfaceAvailability == RenderedSurfaceAvailability.unavailable) {
          return const CaptureFailure(
            CaptureError.renderBoundaryNotFound,
            'Rendered surface is not available for capture',
          );
        }
        // Surface discovery can cross a browser frame on Wasm. Re-establish
        // the same-painted-frame invariant before reading mask coordinates.
        if (surfaceAvailability ==
            RenderedSurfaceAvailability.availableAfterBrowserFrame) {
          await SchedulerBinding.instance.endOfFrame;
        }
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
      final detectedFrameTimeStamp =
          SchedulerBinding.instance.currentSystemFrameTimeStamp;
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

      if (_compressor.capturesRenderedSurface) {
        // Flutter can finish layout/paint before the browser presents those
        // pixels to its canvas. Keep the first geometry as a fence and allow
        // one browser presentation before taking an immutable snapshot. The
        // post-snapshot validation below then spans the entire presentation
        // and snapshot interval. A separate traversal here only samples an
        // intermediate point; the required comparison still happens after the
        // source is immutable, and motion across the interval fails closed.
        final stabilityStart = clock.now();
        await _compressor.waitForRenderedSurfacePresentation();
        lastRenderedSurfaceStabilityValidationTime = clock.now().difference(
          stabilityStart,
        );
      }

      // Initiate the platform snapshot immediately. Because Dart is
      // single-threaded, no other Dart code can execute between mask detection
      // and the toImage/createImageBitmap call.
      final captureTimestamp = clock.now();
      final logicalSize = boundary.size;
      final capturePixelRatio =
          (_compressor.capturesRenderedSurface
                  ? capturePixelRatioFor(logicalSize)
                  : 1.0)
              .clamp(0, _compressor.maximumCapturePixelRatio)
              .toDouble();

      CaptureFailure? snapshotValidationFailure;
      var snapshotValidated = false;
      bool validateSnapshot() {
        snapshotValidated = true;
        final validationStart = clock.now();
        // A browser presentation does not necessarily produce a new Flutter
        // frame. If Flutter's engine-frame timestamp is unchanged, the
        // immutable bitmap can only contain the same rendered geometry that
        // the initial mask walk observed. Avoiding a duplicate walk here is
        // the common static-screen path. Animated, scrolling, or rebuilt
        // screens advance the timestamp and still take the full fail-closed
        // comparison below.
        if (SchedulerBinding.instance.currentSystemFrameTimeStamp ==
            detectedFrameTimeStamp) {
          lastPostSnapshotMaskValidationTime = Duration.zero;
          return true;
        }
        MaskDetectionResult postCaptureResult;
        try {
          final validationDetector = MaskDetector(
            directive: captureDirective,
            trackUnmaskBounds: debugOverlayEnabled,
          );
          postCaptureResult = validationDetector.detectMaskRegions(
            boundary,
            boundaryElement: boundaryElement,
          );
        } catch (error) {
          lastPostSnapshotMaskValidationTime = clock.now().difference(
            validationStart,
          );
          snapshotValidationFailure = CaptureFailure(
            CaptureError.maskDetectionFailed,
            'Post-capture mask detection failed: $error',
          );
          return false;
        }
        lastPostSnapshotMaskValidationTime = clock.now().difference(
          validationStart,
        );

        if (!_maskLayoutMatches(
          before: maskResult,
          beforeViewport: logicalSize,
          after: postCaptureResult,
          afterViewport: boundary.size,
        )) {
          logger.debug(
            'Mask layout changed across browser presentation or while the '
            'image snapshot was created; '
            'discarding the frame',
          );
          snapshotValidationFailure = const CaptureFailure(
            CaptureError.maskDetectionFailed,
            'Layout changed across presentation or capture - masks no longer valid',
          );
          return false;
        }
        return true;
      }

      if (_compressor.capturesRenderedSurface) {
        final imageWidth = (logicalSize.width * capturePixelRatio).ceil();
        final imageHeight = (logicalSize.height * capturePixelRatio).ceil();
        final rasterMaskRegions = _scaleMaskRegions(
          maskRegions,
          scaleX: imageWidth / logicalSize.width,
          scaleY: imageHeight / logicalSize.height,
        );
        final compressedBytes = await _compressor.captureRenderedSurface(
          logicalSize: logicalSize,
          outputWidth: imageWidth,
          outputHeight: imageHeight,
          maskRects: rasterMaskRegions
              .where((region) => region.source != MaskSource.unmask)
              .map((region) => region.bounds)
              .toList(growable: false),
          validateSnapshot: validateSnapshot,
        );
        if (snapshotValidationFailure != null) {
          return snapshotValidationFailure!;
        }
        if (!snapshotValidated) {
          return const CaptureFailure(
            CaptureError.maskDetectionFailed,
            'Rendered surface was not validated after snapshot creation',
          );
        }
        if (compressedBytes == null) {
          return const CaptureFailure(
            CaptureError.compressionFailed,
            'Failed to capture and compress the rendered surface',
          );
        }

        final wireframePayload = _emitWireframes(
          maskResult: maskResult,
          maskRegions: maskRegions,
          viewport: logicalSize,
          timestamp: captureTimestamp,
          sessionId: sessionId,
        );
        final totalTime = clock.now().difference(captureStart);
        logger.debug(
          'Total capture time: ${totalTime.inMilliseconds}ms '
          '(${imageWidth}x$imageHeight raster, '
          '${(compressedBytes.length / 1024).toStringAsFixed(1)}KB)',
        );
        return CaptureSuccess(
          data: compressedBytes,
          width: logicalSize.width.round(),
          height: logicalSize.height.round(),
          maskCount: maskRegions.length,
          timestamp: captureTimestamp,
          maskRegions: maskRegions,
          wireframes: wireframePayload,
          sessionId: sessionId,
          distinctId: distinctId,
        );
      }

      final imageFuture = boundary.toImage(pixelRatio: capturePixelRatio);

      // Wait for image rendering to complete
      ui.Image rawImage;
      try {
        rawImage = await imageFuture;
      } catch (e) {
        return CaptureFailure(
          CaptureError.renderBoundaryNotFound,
          'Failed to capture boundary: $e',
        );
      }
      final renderTime = clock.now().difference(captureTimestamp);
      logger.debug(
        'Image rendering: ${renderTime.inMilliseconds}ms '
        '(${logicalSize.width.round()}x${logicalSize.height.round()} logical → '
        '${rawImage.width}x${rawImage.height} raster)',
      );

      // No post-snapshot validation here: toImage() builds its scene from the
      // layer tree synchronously when called, so the image is the frame the
      // mask walk observed. A second walk after the await would only see
      // later frames and discard valid captures during scrolls and animations.

      // Mask detection, wireframes, and interactions use logical coordinates.
      // Convert only the rectangles painted into the downscaled raster.
      final rasterMaskRegions = _scaleMaskRegions(
        maskRegions,
        scaleX: rawImage.width / logicalSize.width,
        scaleY: rawImage.height / logicalSize.height,
      );

      // Apply masks. Web delegates this to its worker so it does not render a
      // second full-size image on the UI isolate.
      final maskPaintStart = clock.now();
      ui.Image imageForCompression = rawImage;
      if (!_compressor.paintsMasks) {
        try {
          imageForCompression = await _maskPainter.applyMasks(
            rawImage,
            rasterMaskRegions,
          );
          rawImage.dispose();
        } catch (e) {
          rawImage.dispose();
          return CaptureFailure(
            CaptureError.maskApplicationFailed,
            'Failed to apply mask overlays: $e',
          );
        }
      }
      final maskPaintTime = clock.now().difference(maskPaintStart);
      logger.debug('Mask painting: ${maskPaintTime.inMilliseconds}ms');

      // Extract raw RGBA bytes from masked image
      final imageWidth = imageForCompression.width;
      final imageHeight = imageForCompression.height;
      final imageMaskCount = maskRegions.length;
      final byteData = await imageForCompression.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );

      // Clean up Flutter images before compression
      imageForCompression.dispose();

      if (byteData == null) {
        return CaptureFailure(
          CaptureError.insufficientMemory,
          'Failed to get image bytes (OOM)',
        );
      }

      // Platform-specific compression
      final compressionStart = clock.now();
      final rgbaBytes = byteData.buffer.asUint8List();
      final compressedBytes = await _compressor.compress(
        rgbaBytes,
        width: imageWidth,
        height: imageHeight,
        maskRects: _compressor.paintsMasks
            ? rasterMaskRegions
                  .where((region) => region.source != MaskSource.unmask)
                  .map((region) => region.bounds)
                  .toList(growable: false)
            : const [],
      );
      final compressionTime = clock.now().difference(compressionStart);
      logger.debug(
        'Compression: ${compressionTime.inMilliseconds}ms (${compressedBytes?.length ?? 0} bytes)',
      );

      if (compressedBytes == null) {
        return CaptureFailure(
          CaptureError.compressionFailed,
          'Failed to compress image',
        );
      }

      final wireframePayload = _emitWireframes(
        maskResult: maskResult,
        maskRegions: maskRegions,
        viewport: boundary.size,
        timestamp: captureTimestamp,
        sessionId: sessionId,
      );

      final totalTime = clock.now().difference(captureStart);
      logger.debug(
        'Total capture time: ${totalTime.inMilliseconds}ms '
        '(${imageWidth}x$imageHeight raster, '
        '${(compressedBytes.length / 1024).toStringAsFixed(1)}KB)',
      );

      return CaptureSuccess(
        data: compressedBytes,
        width: logicalSize.width.round(),
        height: logicalSize.height.round(),
        maskCount: imageMaskCount,
        timestamp: captureTimestamp,
        maskRegions: maskRegions,
        sessionId: sessionId,
        distinctId: distinctId,
        wireframes: wireframePayload,
      );
    } catch (e) {
      final totalTime = clock.now().difference(captureStart);
      logger.error('Capture failed after ${totalTime.inMilliseconds}ms: $e');
      return CaptureFailure(
        CaptureError.maskDetectionFailed,
        'Unexpected capture error: $e',
      );
    }
  }

  Future<void> dispose() => _compressor.dispose();

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

  static List<MaskRegionInfo> _scaleMaskRegions(
    List<MaskRegionInfo> regions, {
    required double scaleX,
    required double scaleY,
  }) {
    if (scaleX == 1 && scaleY == 1) return regions;
    return regions
        .map(
          (region) => MaskRegionInfo(
            Rect.fromLTRB(
              region.bounds.left * scaleX,
              region.bounds.top * scaleY,
              region.bounds.right * scaleX,
              region.bounds.bottom * scaleY,
            ),
            region.source,
          ),
        )
        .toList(growable: false);
  }

  static bool _maskLayoutMatches({
    required MaskDetectionResult before,
    required Size beforeViewport,
    required MaskDetectionResult after,
    required Size afterViewport,
  }) {
    const tolerance = 0.1;
    bool close(double first, double second) =>
        (first - second).abs() <= tolerance;

    if (after.shouldSkipCapture ||
        !close(beforeViewport.width, afterViewport.width) ||
        !close(beforeViewport.height, afterViewport.height) ||
        before.maskRegions.length != after.maskRegions.length) {
      return false;
    }

    for (var index = 0; index < before.maskRegions.length; index++) {
      final first = before.maskRegions[index];
      final second = after.maskRegions[index];
      if (first.source != second.source ||
          !close(first.bounds.left, second.bounds.left) ||
          !close(first.bounds.top, second.bounds.top) ||
          !close(first.bounds.right, second.bounds.right) ||
          !close(first.bounds.bottom, second.bounds.bottom)) {
        return false;
      }
    }
    return true;
  }
}

enum RenderedSurfaceAvailability {
  available,
  availableAfterBrowserFrame,
  unavailable,
}

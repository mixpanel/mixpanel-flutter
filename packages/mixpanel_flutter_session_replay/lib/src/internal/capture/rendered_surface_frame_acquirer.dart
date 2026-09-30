import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:clock/clock.dart';

import '../../models/masking_directive.dart';
import '../../models/results.dart';
import 'frame_acquirer.dart';
import 'raster_completion_barrier.dart';
import 'rendered_surface_capture.dart';

/// Acquisition from the surface the platform already presented (web).
///
/// Flutter can finish layout and paint before the browser presents those
/// pixels, so the snapshot always lags the mask walk. This acquirer waits one
/// presentation, takes an immutable snapshot, and only encodes it once the
/// [MaskLayoutFence] confirms the masks still hold across that interval.
class RenderedSurfaceFrameAcquirer extends FrameAcquirer {
  /// Maximum raster area captured from the rendered surface.
  ///
  /// 1280x720 is comfortably above normal phone viewports while bounding the
  /// work caused by large browser viewports.
  static const int maxRasterPixels = 1280 * 720;

  /// Secondary bound for pathological ultra-wide or ultra-tall viewports.
  static const double maxRasterLongEdge = 1920;

  final RenderedSurfaceCapture _surface;

  /// Duration of the most recent wait for browser presentation, exposed for
  /// integration performance validation.
  Duration? lastPresentationWaitTime;

  final RasterCompletionBarrier? _rasterCompletion;

  RenderedSurfaceFrameAcquirer(
    this._surface, {
    RasterCompletionBarrier? rasterCompletion,
  }) : _rasterCompletion = rasterCompletion;

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

  @override
  bool get isAvailable => _surface.isAvailable;

  /// The [MaskLayoutFence] rejects frames taken during motion, so the settled
  /// screen needs a follow-up.
  @override
  bool get followsUpFramesDuringCapture => true;

  /// Discovers the surface, then synchronizes skwasm before masks are read.
  /// CanvasKit uses only the browser presentation wait in [acquire].
  @override
  Future<FrameSourceStatus> prepare(Size logicalSize) async {
    final availability = await _surface.waitUntilRenderedSurfaceAvailable(
      logicalSize,
    );
    if (availability == RenderedSurfaceAvailability.unavailable) {
      return FrameSourceStatus.unavailable;
    }
    if (_rasterCompletion case final barrier?) {
      if (!await barrier.prepare()) return FrameSourceStatus.unavailable;
      return FrameSourceStatus.readyAfterPlatformFrame;
    }
    return switch (availability) {
      RenderedSurfaceAvailability.available => FrameSourceStatus.ready,
      // Surface discovery can cross a browser frame on Wasm.
      RenderedSurfaceAvailability.availableAfterBrowserFrame =>
        FrameSourceStatus.readyAfterPlatformFrame,
      RenderedSurfaceAvailability.unavailable => FrameSourceStatus.unavailable,
    };
  }

  @override
  Future<FrameAcquisition> acquire(FrameRequest request) async {
    if (_rasterCompletion case final barrier?) {
      if (request.isCancelled()) {
        return const FrameRejected(cancelledCaptureFailure);
      }
      final acknowledged = await barrier.waitForCurrentFrame();
      if (request.isCancelled()) {
        return const FrameRejected(cancelledCaptureFailure);
      }
      if (!acknowledged) {
        return const FrameRejected(
          CaptureFailure(
            CaptureError.maskDetectionFailed,
            'The frame used to read masks has not finished rasterizing',
          ),
        );
      }
    }
    // Keep the mask walk's geometry as a fence and allow one browser
    // presentation before taking an immutable snapshot. The fence check below
    // then spans the entire presentation and snapshot interval, so motion
    // across it fails closed.
    final presentationStart = clock.now();
    await _surface.waitForRenderedSurfacePresentation();
    lastPresentationWaitTime = clock.now().difference(presentationStart);
    // The stop may have happened during that wait; the sensitive screen
    // shown afterward must not be acquired at all.
    if (request.isCancelled()) {
      return const FrameRejected(cancelledCaptureFailure);
    }

    final capturedAt = clock.now();
    final logicalSize = request.logicalSize;
    final ratio = capturePixelRatioFor(
      logicalSize,
    ).clamp(0, _surface.maximumCapturePixelRatio).toDouble();
    final width = (logicalSize.width * ratio).ceil();
    final height = (logicalSize.height * ratio).ceil();
    final maskRects =
        scaleMaskRegions(
              request.maskRegions,
              scaleX: width / logicalSize.width,
              scaleY: height / logicalSize.height,
            )
            .where((region) => region.source != MaskSource.unmask)
            .map((region) => region.bounds)
            .toList(growable: false);

    final snapshot = await _surface.capture(
      logicalSize: logicalSize,
      outputWidth: width,
      outputHeight: height,
    );
    if (snapshot == null) {
      return const FrameRejected(
        CaptureFailure(
          CaptureError.renderBoundaryNotFound,
          'Rendered surface is not available for capture',
        ),
      );
    }
    Uint8List? encoded;
    try {
      if (request.isCancelled()) {
        return const FrameRejected(cancelledCaptureFailure);
      }
      if (request.fence.check() case final failure?) {
        return FrameRejected(failure);
      }
      encoded = await snapshot.encode(maskRects: maskRects);
    } finally {
      snapshot.dispose();
    }
    if (encoded == null) {
      return const FrameRejected(
        CaptureFailure(
          CaptureError.compressionFailed,
          'Failed to capture and compress the rendered surface',
        ),
      );
    }
    return AcquiredFrame(
      data: encoded,
      width: width,
      height: height,
      capturedAt: capturedAt,
    );
  }

  @override
  Future<void> dispose() async {
    _rasterCompletion?.dispose();
    await _surface.dispose();
  }
}

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import '../../models/masking_directive.dart';
import '../../models/results.dart';
import 'mask_layout_fence.dart';

/// Turns the frame a mask walk observed into encoded, masked pixels.
///
/// [ScreenshotCapturer] owns what every platform shares: the paint fence,
/// identity pinning, mask detection, wireframes and the capture result. An
/// acquirer owns only how its platform reads, masks and encodes pixels.
abstract class FrameAcquirer {
  /// Whether frames can still be acquired. Implementations switch this to
  /// false after a permanent failure so capture stops before any work.
  bool get isAvailable;

  /// Whether a frame that renders while a capture runs is followed up with
  /// one more capture once it completes.
  ///
  /// An acquirer whose pixels can lag the mask walk rejects frames taken
  /// during motion, so the screen a scroll or animation settles on often
  /// arrives during a rejected capture. Without a follow-up it would go
  /// unrecorded until something else repaints.
  ///
  /// A follow-up also means capture never requests a frame of its own: that
  /// frame would count as one rendered during the capture and re-arm it
  /// forever on a static screen. When false, every capture waits for a
  /// painted frame, requesting one if the scheduler is idle, and frames that
  /// render during a capture are dropped.
  bool get followsUpFramesDuringCapture => false;

  /// Runs before the mask walk, once Flutter has finished painting.
  ///
  /// Synchronous by default so capture does not yield between the paint
  /// fence and the mask walk when there is nothing to wait for.
  FutureOr<FrameSourceStatus> prepare(Size logicalSize) =>
      FrameSourceStatus.ready;

  /// Acquires the frame described by [request].
  ///
  /// Called synchronously after the mask walk; implementations that snapshot
  /// Flutter's layer tree must do so before their first await.
  Future<FrameAcquisition> acquire(FrameRequest request);

  Future<void> dispose();
}

enum FrameSourceStatus {
  ready,

  /// Ready, but waiting crossed a platform frame. The render tree must be
  /// re-fenced before masks are read.
  readyAfterPlatformFrame,

  unavailable,
}

/// Everything an acquirer needs about the frame the mask walk observed.
class FrameRequest {
  final RenderRepaintBoundary boundary;
  final Size logicalSize;

  /// Mask regions in logical coordinates.
  final List<MaskRegionInfo> maskRegions;

  /// Re-checks the masks against the current render tree. An acquirer whose
  /// pixels can lag the mask walk must pass it before encoding.
  final MaskLayoutFence fence;

  /// True once recording stopped or paused. Polled after every await before
  /// pixels are acquired and before they are encoded.
  final bool Function() isCancelled;

  const FrameRequest({
    required this.boundary,
    required this.logicalSize,
    required this.maskRegions,
    required this.fence,
    required this.isCancelled,
  });
}

sealed class FrameAcquisition {
  const FrameAcquisition();
}

final class AcquiredFrame extends FrameAcquisition {
  /// Encoded image bytes.
  final Uint8List data;

  /// Raster dimensions of [data].
  final int width;
  final int height;

  /// When the pixels were taken.
  final DateTime capturedAt;

  const AcquiredFrame({
    required this.data,
    required this.width,
    required this.height,
    required this.capturedAt,
  });
}

final class FrameRejected extends FrameAcquisition {
  final CaptureFailure failure;

  const FrameRejected(this.failure);
}

const cancelledCaptureFailure = CaptureFailure(
  CaptureError.cancelled,
  'Recording stopped or paused while the frame was in flight',
);

/// Converts logical mask regions to raster coordinates.
List<MaskRegionInfo> scaleMaskRegions(
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

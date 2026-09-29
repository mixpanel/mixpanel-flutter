import 'dart:ui' as ui;

import 'package:clock/clock.dart';

import '../logger.dart';
import '../masking/mask_painter.dart';
import '../../models/results.dart';
import 'frame_acquirer.dart';
import 'image_compressor.dart';

/// Native acquisition: renders Flutter's layer tree with
/// `RenderRepaintBoundary.toImage`, paints masks, and hands RGBA bytes to an
/// [ImageCompressor].
///
/// No post-snapshot mask check is needed: `toImage()` builds its scene from
/// the layer tree synchronously when called, so the image is the frame the
/// mask walk observed. A second walk after the await would only see later
/// frames and discard valid captures during scrolls and animations.
///
/// For the same reason the frame counts as acquired as soon as `toImage()` is
/// called, and cancellation is not checked after it.
class ToImageFrameAcquirer extends FrameAcquirer {
  final ImageCompressor _compressor;
  final MixpanelLogger _logger;
  final MaskPainter _maskPainter = MaskPainter();

  ToImageFrameAcquirer(this._compressor, {required MixpanelLogger logger})
    : _logger = logger;

  @override
  bool get isAvailable => _compressor.isAvailable;

  @override
  Future<FrameAcquisition> acquire(FrameRequest request) async {
    // Snapshot before the first await: no other Dart code may run between
    // the mask walk and toImage().
    final capturedAt = clock.now();
    final logicalSize = request.logicalSize;
    final imageFuture = request.boundary.toImage(pixelRatio: 1);

    ui.Image rawImage;
    try {
      rawImage = await imageFuture;
    } catch (e) {
      return FrameRejected(
        CaptureFailure(
          CaptureError.renderBoundaryNotFound,
          'Failed to capture boundary: $e',
        ),
      );
    }
    // Not cancelled here: the pixels were fixed when toImage() was called,
    // before the await, so they cannot show a screen from after a stop. A
    // stop keeps an acquired frame under the replay it was captured for,
    // like the native SDKs; the coordinator discards it only across a pause.
    final renderTime = clock.now().difference(capturedAt);
    _logger.debug(
      'Image rendering: ${renderTime.inMilliseconds}ms '
      '(${logicalSize.width.round()}x${logicalSize.height.round()} logical → '
      '${rawImage.width}x${rawImage.height} raster)',
    );

    final rasterMaskRegions = scaleMaskRegions(
      request.maskRegions,
      scaleX: rawImage.width / logicalSize.width,
      scaleY: rawImage.height / logicalSize.height,
    );

    final maskPaintStart = clock.now();
    final ui.Image maskedImage;
    try {
      maskedImage = await _maskPainter.applyMasks(rawImage, rasterMaskRegions);
    } catch (e) {
      return FrameRejected(
        CaptureFailure(
          CaptureError.maskApplicationFailed,
          'Failed to apply mask overlays: $e',
        ),
      );
    } finally {
      rawImage.dispose();
    }
    _logger.debug(
      'Mask painting: ${clock.now().difference(maskPaintStart).inMilliseconds}ms',
    );

    final width = maskedImage.width;
    final height = maskedImage.height;
    final byteData = await maskedImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    maskedImage.dispose();
    if (byteData == null) {
      return const FrameRejected(
        CaptureFailure(
          CaptureError.insufficientMemory,
          'Failed to get image bytes (OOM)',
        ),
      );
    }

    final compressionStart = clock.now();
    final compressedBytes = await _compressor.compress(
      byteData.buffer.asUint8List(),
      width: width,
      height: height,
    );
    _logger.debug(
      'Compression: ${clock.now().difference(compressionStart).inMilliseconds}ms '
      '(${compressedBytes?.length ?? 0} bytes)',
    );
    if (compressedBytes == null) {
      return const FrameRejected(
        CaptureFailure(
          CaptureError.compressionFailed,
          'Failed to compress image',
        ),
      );
    }
    return AcquiredFrame(
      data: compressedBytes,
      width: width,
      height: height,
      capturedAt: capturedAt,
    );
  }

  @override
  Future<void> dispose() => _compressor.dispose();
}

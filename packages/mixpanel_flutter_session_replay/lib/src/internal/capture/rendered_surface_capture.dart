import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

/// Discovers and snapshots the surface a platform has already presented.
///
/// This is the platform seam beneath `RenderedSurfaceFrameAcquirer`, which
/// owns raster sizing and mask validation. Only web implements it.
abstract class RenderedSurfaceCapture {
  bool get isAvailable;
  double get maximumCapturePixelRatio => 1;

  /// Discovers the surface and requests any fresh rendering needed before
  /// reading masks. WebGL buffers can expire after browser presentation, so
  /// callers must proceed to snapshot without unrelated asynchronous work.
  Future<RenderedSurfaceAvailability> waitUntilRenderedSurfaceAvailable(
    Size logicalSize,
  ) async => RenderedSurfaceAvailability.available;

  /// Waits for presentation only when the prepared surface needs it and its
  /// readable buffer survives it.
  Future<void> waitForRenderedSurfacePresentation() async {}

  /// Returns an owned snapshot ready for mask validation, or null if the source
  /// surface cannot be identified. Acquisition never encodes or uploads pixels.
  Future<CapturedSurface?> capture({
    required Size logicalSize,
    required int outputWidth,
    required int outputHeight,
  });

  Future<void> dispose();
}

/// An immutable frame whose platform resources must be released by the caller.
/// Encode only after mask validation. Encoding consumes the frame once; dispose
/// also releases frames rejected by validation or abandoned due to an error.
abstract class CapturedSurface {
  Future<Uint8List?> encode({required List<Rect> maskRects});
  void dispose();
}

enum RenderedSurfaceAvailability {
  available,
  availableAfterBrowserFrame,
  unavailable,
}

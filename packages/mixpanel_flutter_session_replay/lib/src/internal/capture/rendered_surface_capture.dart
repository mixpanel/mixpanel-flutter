import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

/// Acquires immutable platform frames; the screenshot coordinator owns mask
/// detection and validation. Native capture uses RepaintBoundary.toImage.
abstract class RenderedSurfaceCapture {
  bool get isAvailable;
  double get maximumCapturePixelRatio => 1;

  Future<RenderedSurfaceAvailability> waitUntilRenderedSurfaceAvailable(
    Size logicalSize,
  ) async => RenderedSurfaceAvailability.available;

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

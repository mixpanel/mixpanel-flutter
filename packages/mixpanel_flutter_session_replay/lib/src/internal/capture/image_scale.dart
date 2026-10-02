import 'dart:ui' show Offset, Size;

/// Image pixels per logical pixel for a frame, as `Offset(x, y)`.
///
/// Replay coordinates — metadata, interactions, and wireframes — are uploaded
/// in image pixels, so render-tree geometry is scaled by this before it ships.
/// Both axes are derived separately because a raster is rounded up to whole
/// pixels independently per axis.
///
/// Returns `Offset(1, 1)` for a degenerate viewport, leaving coordinates
/// untouched rather than collapsing them onto zero.
Offset imageScaleBetween({required Size viewport, required Size image}) {
  if (!viewport.isFinite ||
      !image.isFinite ||
      viewport.width <= 0 ||
      viewport.height <= 0) {
    return const Offset(1, 1);
  }
  return Offset(image.width / viewport.width, image.height / viewport.height);
}

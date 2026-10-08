import 'dart:ui' show Offset, Size;

import '../../models/debug_overlay_colors.dart';
import '../../models/masking_directive.dart';

import 'debug_overlay_host_stub.dart'
    if (dart.library.js_interop) 'debug_overlay_host_web.dart'
    as impl;

/// Draws the debug mask overlay outside the surface session replay captures.
///
/// Web capture reads one Flutter `<canvas>` backing store, so rectangles
/// painted into the Flutter tree would be baked into the uploaded replay.
/// A host draws them as sibling DOM nodes instead, which the capture cannot
/// see — so the overlay never has to be hidden while a capture runs.
abstract interface class DebugOverlayHost {
  /// Redraws [regions] over the Flutter view.
  ///
  /// [regions] are logical pixels relative to the capture boundary's top-left,
  /// which [boundaryOrigin] and [boundarySize] place within the view.
  void update({
    required List<MaskRegionInfo> regions,
    required DebugOverlayColors colors,
    required Offset boundaryOrigin,
    required Size boundarySize,
  });

  /// Removes the overlay from the page.
  void dispose();
}

/// Creates a host for the current platform.
///
/// Returns null wherever capture reads the Flutter render tree directly;
/// those platforms keep using the in-tree `MaskOverlay` widget.
DebugOverlayHost? createDebugOverlayHost() => impl.createDebugOverlayHost();

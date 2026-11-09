import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/debug_overlay_colors.dart';
import '../models/masking_directive.dart';
import '../widgets/mask_overlay.dart';
import 'platform/debug_overlay_host.dart';

/// Builds the debug mask overlay for one capture boundary.
///
/// [regions] are logical pixels relative to the boundary's top-left, and
/// [boundary] returns that boundary's render box once it has been laid out.
typedef DebugMaskOverlayFactory =
    DebugMaskOverlay Function({
      required ValueListenable<List<MaskRegionInfo>> regions,
      required DebugOverlayColors colors,
      required RenderBox? Function() boundary,
    });

/// Draws the debug mask overlay where the replay capture cannot see it.
///
/// Platform initialization picks the strategy that matches its capture, so
/// the widget that hosts the overlay never needs to know how pixels are read.
abstract class DebugMaskOverlay {
  /// Wraps the captured subtree. In-tree strategies paint the overlay here.
  Widget wrap(Widget capturedSubtree) => capturedSubtree;

  /// Called after every rendered frame, so an overlay positioned outside the
  /// Flutter tree can follow the boundary as it scrolls, resizes, or moves.
  void onFrame() {}

  void dispose() {}
}

/// Paints the overlay into the Flutter tree, above the capture boundary.
///
/// For captures that render the boundary's own subtree, which excludes
/// anything painted above it.
class InTreeDebugMaskOverlay extends DebugMaskOverlay {
  final ValueListenable<List<MaskRegionInfo>> _regions;
  final DebugOverlayColors _colors;

  InTreeDebugMaskOverlay({
    required ValueListenable<List<MaskRegionInfo>> regions,
    required DebugOverlayColors colors,
    required RenderBox? Function() boundary,
  }) : _regions = regions,
       _colors = colors;

  @override
  Widget wrap(Widget capturedSubtree) =>
      ValueListenableBuilder<List<MaskRegionInfo>>(
        valueListenable: _regions,
        builder: (context, maskRegions, child) => MaskOverlay(
          maskRegions: maskRegions,
          colors: _colors,
          child: child!,
        ),
        child: capturedSubtree,
      );
}

/// Draws the overlay outside the rendered surface the capture reads.
///
/// For captures that read the presented surface, where anything painted into
/// the Flutter tree would be baked into the replay. Nothing is ever painted
/// in-tree, even when no host can be created, so the diagnostic paint can
/// never leak into an upload. Redrawing touches the host directly, off
/// Flutter's build pipeline, so the overlay cannot schedule the frame that
/// would trigger the next capture.
class OutOfSurfaceDebugMaskOverlay extends DebugMaskOverlay {
  final ValueListenable<List<MaskRegionInfo>> _regions;
  final DebugOverlayColors _colors;
  final RenderBox? Function() _boundary;
  final DebugOverlayHost? _host;

  OutOfSurfaceDebugMaskOverlay({
    required ValueListenable<List<MaskRegionInfo>> regions,
    required DebugOverlayColors colors,
    required RenderBox? Function() boundary,
    DebugOverlayHost? host,
  }) : _regions = regions,
       _colors = colors,
       _boundary = boundary,
       _host = host ?? createDebugOverlayHost() {
    if (_host == null) return;
    _regions.addListener(_redraw);
    // The notifier only fires on change, and the coordinator suppresses a
    // capture whose regions match the stored ones. Paint the current value
    // once so a host attached to an already-populated notifier is not blank
    // until the layout happens to move.
    WidgetsBinding.instance.addPostFrameCallback((_) => _redraw());
  }

  bool _disposed = false;

  // The region coordinates are local to the capture boundary, so a frame that
  // moved the boundary must reposition otherwise-unchanged regions.
  @override
  void onFrame() => _redraw();

  void _redraw() {
    final host = _host;
    if (_disposed || host == null) return;
    final boundary = _boundary();
    if (boundary == null || !boundary.hasSize) return;
    host.update(
      regions: _regions.value,
      colors: _colors,
      boundaryOrigin: boundary.localToGlobal(Offset.zero),
      boundarySize: boundary.size,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _regions.removeListener(_redraw);
    _host?.dispose();
  }
}

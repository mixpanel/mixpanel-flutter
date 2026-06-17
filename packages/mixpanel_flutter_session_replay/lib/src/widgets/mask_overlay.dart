import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../models/debug_overlay_colors.dart';
import '../models/masking_directive.dart';

/// Debug overlay that displays mask regions as colored rectangles
///
/// This widget is used for debugging purposes to visualize which regions
/// are being masked during session replay. The overlay is non-interactive
/// and will not block user interactions.
///
/// Different mask sources are shown in different colors:
/// - Unmask regions: Configurable (default: Green)
/// - Auto masks (text/images): Configurable (default: Orange)
/// - Manual/Security masks: Configurable (default: Red)
///
/// All regions are drawn opaquely onto a single layer, then composited
/// with uniform transparency. This prevents overlapping regions from
/// compounding opacity.
class MaskOverlay extends StatelessWidget {
  const MaskOverlay({
    super.key,
    required this.maskRegions,
    required this.child,
    required this.colors,
  });

  /// List of mask regions with source information
  final List<MaskRegionInfo> maskRegions;

  /// The child widget to overlay masks on
  final Widget child;

  /// Color configuration for the overlay
  final DebugOverlayColors colors;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topLeft,
      children: [
        // The actual app content
        child,
        // Overlay that shows mask regions (non-interactive)
        IgnorePointer(
          child: Opacity(
            opacity: colors.opacity,
            child: CustomPaint(
              painter: _MaskRegionsPainter(maskRegions, colors),
              child: Container(),
            ),
          ),
        ),
      ],
    );
  }
}

/// Custom painter that draws colored rectangles for each mask region
///
/// Draws regions in priority order: unmask (lowest), auto, manual (highest).
/// All rects are drawn opaque — the parent [Opacity] widget handles transparency.
class _MaskRegionsPainter extends CustomPainter {
  _MaskRegionsPainter(this.maskRegions, this.colors);

  final List<MaskRegionInfo> maskRegions;
  final DebugOverlayColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw in priority order: unmask first, then auto, then manual on top
    for (final region in maskRegions) {
      if (region.source == MaskSource.unmask) {
        _drawRegion(canvas, region);
      }
    }
    for (final region in maskRegions) {
      if (region.source == MaskSource.auto) {
        _drawRegion(canvas, region);
      }
    }
    for (final region in maskRegions) {
      if (region.source == MaskSource.manual ||
          region.source == MaskSource.security) {
        _drawRegion(canvas, region);
      }
    }
  }

  void _drawRegion(Canvas canvas, MaskRegionInfo maskInfo) {
    final color = _getColorForSource(maskInfo.source);

    // Skip drawing if color is null (disabled visualization for this type)
    if (color == null) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawRect(maskInfo.bounds, paint);
  }

  /// Get color for a mask source (null if visualization disabled for this type)
  Color? _getColorForSource(MaskSource source) {
    switch (source) {
      case MaskSource.auto:
        return colors.autoMaskColor;
      case MaskSource.manual:
      case MaskSource.security:
        return colors.maskColor;
      case MaskSource.unmask:
        return colors.unmaskColor;
    }
  }

  @override
  bool shouldRepaint(_MaskRegionsPainter oldDelegate) {
    return !listEquals(maskRegions, oldDelegate.maskRegions) ||
        colors != oldDelegate.colors;
  }
}

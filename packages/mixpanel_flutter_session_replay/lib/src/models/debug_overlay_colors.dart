import 'package:flutter/material.dart';

/// Debug configuration options for Session Replay
///
/// Houses debug-related settings like overlay visualization.
/// When null in [SessionReplayOptions], all debug features are disabled.
class DebugOptions {
  const DebugOptions({this.overlayColors = const DebugOverlayColors()});

  /// Color configuration for the mask overlay visualization.
  ///
  /// When non-null, displays a colored overlay showing masked regions
  /// in real-time. Useful for debugging masking issues.
  ///
  /// When null, overlay is disabled.
  final DebugOverlayColors? overlayColors;
}

/// Color configuration for debug mask overlay
///
/// Controls the colors used to visualize different types of mask regions.
/// Individual colors can be null to hide that mask type from visualization.
class DebugOverlayColors {
  const DebugOverlayColors({
    this.maskColor = Colors.red,
    this.autoMaskColor = Colors.orange,
    this.unmaskColor = Colors.green,
    this.opacity = 0.5,
  });

  /// Color for manually masked regions (MixpanelMask and security-enforced)
  ///
  /// Includes both:
  /// - Regions masked using MixpanelMask widget
  /// - Security-enforced masks (RenderEditable/input fields)
  ///
  /// When null, manual/security-masked regions are not shown in the overlay.
  /// Default: Colors.red
  final Color? maskColor;

  /// Color for auto-masked regions (text and images)
  ///
  /// When null, auto-masked regions are not shown in the overlay.
  /// Default: Colors.orange
  final Color? autoMaskColor;

  /// Color for unmask regions (MixpanelUnmask areas)
  ///
  /// Shows areas that are explicitly excluded from auto-masking.
  /// Helps verify that MixpanelUnmask widgets are positioned correctly.
  ///
  /// When null, unmask regions are not shown in the overlay.
  /// Default: Colors.green
  final Color? unmaskColor;

  /// Opacity of the overlay layer (0.0 = fully transparent, 1.0 = fully opaque)
  ///
  /// Default: 0.5
  final double opacity;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DebugOverlayColors &&
          maskColor == other.maskColor &&
          autoMaskColor == other.autoMaskColor &&
          unmaskColor == other.unmaskColor &&
          opacity == other.opacity;

  @override
  int get hashCode =>
      Object.hash(maskColor, autoMaskColor, unmaskColor, opacity);
}

import 'dart:ui';

import 'configuration.dart';

/// Source/reason why a region was masked or unmasked
enum MaskSource {
  /// Auto-masked (text or image based on autoMaskTypes configuration)
  auto,

  /// Manually masked using MixpanelMask widget
  manual,

  /// Security-enforced mask (e.g., RenderEditable/input fields)
  security,

  /// Explicitly unmasked using MixpanelUnmask widget
  unmask,
}

/// Represents a masked region with information about why it was masked
class MaskRegionInfo {
  /// Bounding rectangle for the masked area
  final Rect bounds;

  /// Why this region was masked
  final MaskSource source;

  MaskRegionInfo(this.bounds, this.source);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MaskRegionInfo &&
          bounds == other.bounds &&
          source == other.source;

  @override
  int get hashCode => Object.hash(bounds, source);

  @override
  String toString() => 'MaskRegionInfo(bounds: $bounds, source: $source)';
}

/// Represents a masked region in the UI (for MaskWidget ancestry tracking)
class MaskRegion {
  /// Bounding rectangle for the masked area
  final Rect bounds;

  /// Widget hash code for identity checking
  final int widgetHashCode;

  MaskRegion(this.bounds, this.widgetHashCode);

  /// Check if this region overlaps with another rectangle
  bool contains(Rect other) {
    return bounds.overlaps(other);
  }

  @override
  String toString() => 'MaskRegion(bounds: $bounds, hash: $widgetHashCode)';
}

/// Widget type for masking decisions
enum WidgetType { text, image, other }

/// Configuration determining what should be masked
class MaskingDirective {
  /// Widget types to auto-mask
  final Set<AutoMaskedView> autoMaskTypes;

  /// Explicitly masked regions from MixpanelMask widgets
  final List<MaskRegion> manualMaskRegions;

  /// Explicitly unmasked regions from MixpanelUnmask widgets
  final List<MaskRegion> unmaskedRegions;

  MaskingDirective({
    required this.autoMaskTypes,
    this.manualMaskRegions = const [],
    this.unmaskedRegions = const [],
  });

  /// Determine if a widget should be masked
  ///
  /// Precedence (highest to lowest):
  /// 1. Manual Unmask (MixpanelUnmask) - returns false
  /// 2. Manual Mask (MixpanelMask) - returns true
  /// 3. Auto-Mask (based on widget type) - returns true if type is in autoMaskTypes
  ///
  /// For nested directives, innermost takes precedence
  bool shouldMask(Rect bounds, WidgetType type, {bool isInsideUnmask = false}) {
    // Check unmask regions first (highest precedence)
    if (unmaskedRegions.any((region) => region.contains(bounds))) {
      return false;
    }

    // Check manual mask regions
    if (manualMaskRegions.any((region) => region.contains(bounds))) {
      return true;
    }

    // Check auto-masking (lowest precedence)
    if (isInsideUnmask) return false;

    return autoMaskTypes.contains(_widgetTypeToAutoMaskView(type));
  }

  /// Convert WidgetType to AutoMaskedView
  AutoMaskedView? _widgetTypeToAutoMaskView(WidgetType type) {
    switch (type) {
      case WidgetType.text:
        return AutoMaskedView.text;
      case WidgetType.image:
        return AutoMaskedView.image;
      case WidgetType.other:
        return null;
    }
  }

  /// Create a copy with updated regions
  MaskingDirective copyWith({
    Set<AutoMaskedView>? autoMaskTypes,
    List<MaskRegion>? manualMaskRegions,
    List<MaskRegion>? unmaskedRegions,
  }) {
    return MaskingDirective(
      autoMaskTypes: autoMaskTypes ?? this.autoMaskTypes,
      manualMaskRegions: manualMaskRegions ?? this.manualMaskRegions,
      unmaskedRegions: unmaskedRegions ?? this.unmaskedRegions,
    );
  }

  @override
  String toString() {
    return 'MaskingDirective(autoMask: $autoMaskTypes, '
        'manualMasks: ${manualMaskRegions.length}, '
        'unmasks: ${unmaskedRegions.length})';
  }
}

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../models/masking_directive.dart';
import '../../widgets/widgets.dart';

/// Mask context propagated down the tree during traversal.
enum MaskContext {
  /// No explicit directive — auto-masking rules apply.
  none,

  /// Inside MixpanelMask — all descendants are masked individually.
  mask,

  /// Inside MixpanelUnmask — auto-masking is suppressed (except TextField).
  unmask,
}

/// Result of mask detection
class MaskDetectionResult {
  /// Mask regions to apply with source information
  final List<MaskRegionInfo> maskRegions;

  /// Whether the capture should be skipped due to visual state that
  /// would cause mask coordinate mismatch (route transitions, overscroll stretch).
  final bool shouldSkipCapture;

  MaskDetectionResult({
    required this.maskRegions,
    this.shouldSkipCapture = false,
  });
}

/// Detects widgets that should be masked in screenshots
class MaskDetector {
  static final Map<Type, String> _widgetTypeNames = <Type, String>{};

  /// Configuration for auto-masking
  final MaskingDirective directive;

  /// Whether to track unmask region bounds for debug overlay
  final bool trackUnmaskBounds;

  MaskDetector({required this.directive, this.trackUnmaskBounds = false});

  /// Traverse widget tree and collect mask regions
  ///
  /// Returns MaskDetectionResult with regions and bounds snapshot, or throws on error
  MaskDetectionResult detectMaskRegions(
    RenderRepaintBoundary boundary, {
    Element? boundaryElement,
  }) {
    final maskRegions = <MaskRegionInfo>[];
    final traversalState = _MaskTraversalState();

    try {
      // Production callers already own the boundary element. The fallback is
      // retained for direct detector callers and performance comparisons.
      final resolvedBoundaryElement =
          boundaryElement ?? _findElementForRenderObject(boundary);
      if (resolvedBoundaryElement == null) {
        return MaskDetectionResult(maskRegions: []);
      }

      // Traverse descendants once, collecting masks and detecting visual states
      // that make their coordinates unsafe to apply to the captured image.
      _traverseElementTree(
        resolvedBoundaryElement,
        boundary,
        maskRegions,
        traversalState: traversalState,
        maskContext: MaskContext.none,
        tickerEnabled: true, // Start with enabled (active route)
        viewportBounds: null, // Will be detected and cached during traversal
      );
    } catch (e) {
      // Mask detection failed - fail safe, don't capture
      throw MaskDetectionException('Widget tree traversal failed: $e');
    }

    return MaskDetectionResult(
      maskRegions: maskRegions,
      shouldSkipCapture: traversalState.shouldSkipCapture,
    );
  }

  /// Find the Element that owns the given RenderObject
  Element? _findElementForRenderObject(RenderObject renderObject) {
    Element? result;

    void visitor(Element element) {
      if (element.renderObject == renderObject) {
        result = element;
        return;
      }
      element.debugVisitOnstageChildren(visitor);
    }

    WidgetsBinding.instance.rootElement?.debugVisitOnstageChildren(visitor);
    return result;
  }

  /// Recursively traverse element tree to find maskable widgets
  ///
  /// Tracks TickerMode state down the tree to efficiently filter background Navigator routes
  void _traverseElementTree(
    Element element,
    RenderRepaintBoundary boundary,
    List<MaskRegionInfo> maskRegions, {
    required _MaskTraversalState traversalState,
    required MaskContext maskContext,
    required bool tickerEnabled,
    Rect?
    viewportBounds, // Cached viewport bounds (detected once, reused for all children)
  }) {
    final widget = element.widget;

    if (_hasUnsafeVisualState(widget)) {
      traversalState.shouldSkipCapture = true;
    }

    // PERFORMANCE: Track TickerMode state as we traverse (no expensive ancestor walks)
    // Navigator wraps background routes in TickerMode(enabled: false)
    bool currentTickerEnabled = tickerEnabled;
    if (widget is TickerMode) {
      currentTickerEnabled = widget.enabled;
    }

    // Skip entire subtree if tickers are disabled (background Navigator route)
    if (!currentTickerEnabled) {
      return;
    }

    // PERFORMANCE: Detect and cache viewport bounds when entering a scrollable container
    // This avoids repeated tree walks for all children inside the same viewport
    Rect? currentViewportBounds = viewportBounds;
    if (currentViewportBounds == null) {
      final renderObject = element.renderObject;
      final widget = element.widget;

      // Detect scrollable viewports by widget type (fast) or render object name (slower fallback)
      // Covers: SingleChildScrollView, ListView, GridView, CustomScrollView, PageView, TabBarView, NestedScrollView, ReorderableListView, TableView
      const scrollablePatterns = [
        'ScrollView',
        'ListView',
        'GridView',
        'PageView',
        'TableView',
      ];

      final widgetTypeName = widget.runtimeType.toString();
      final isScrollable =
          scrollablePatterns.any(
            (pattern) => widgetTypeName.contains(pattern),
          ) ||
          (renderObject != null &&
              renderObject.runtimeType.toString().contains('RenderViewport'));

      if (isScrollable && renderObject is RenderBox && renderObject.hasSize) {
        try {
          final viewportGlobalOffset = renderObject.localToGlobal(Offset.zero);
          final boundaryGlobalOffset = boundary.localToGlobal(Offset.zero);
          final viewportOffset = viewportGlobalOffset - boundaryGlobalOffset;

          currentViewportBounds = Rect.fromLTWH(
            viewportOffset.dx,
            viewportOffset.dy,
            renderObject.size.width,
            renderObject.size.height,
          );
        } catch (_) {
          // If we can't get coordinates, continue with null (assume visible)
        }
      }
    }

    // VISIBILITY FILTERING
    // debugVisitOnstageChildren handles: Offstage, Overlay, IndexedStack, ListView/GridView viewport filtering
    // We still need manual checks for widgets that don't override debugVisitOnstageChildren:

    // Check if this specific widget is explicitly hidden via Visibility
    if (widget is Visibility && !widget.visible) {
      return; // Skip this widget and all children
    }

    // Check if this specific widget has near-zero opacity
    if (widget is Opacity && widget.opacity < 0.001) {
      return; // Skip this widget and all children
    }

    // --- Masking decision ---
    MaskContext currentContext = maskContext;

    // SECURITY: TextField is always masked regardless of context or directives
    if (element.renderObject is RenderEditable) {
      _addElementToMaskRects(
        element,
        boundary,
        maskRegions,
        MaskSource.security,
      );
    } else if (widget is MixpanelMask) {
      // Container rect covers MixpanelMask's own bounds
      _addElementToMaskRects(element, boundary, maskRegions, MaskSource.manual);
      // Propagate context=mask to all descendants
      currentContext = MaskContext.mask;
    } else if (widget is MixpanelUnmask) {
      // Record unmask region bounds for visualization (only if debug overlay is enabled)
      if (trackUnmaskBounds) {
        _addElementToMaskRects(
          element,
          boundary,
          maskRegions,
          MaskSource.unmask,
        );
      }
      // Propagate context=unmask to all descendants
      currentContext = MaskContext.unmask;
    } else {
      switch (currentContext) {
        case MaskContext.mask:
          // Every node under mask context gets its own mask rect
          _addElementToMaskRects(
            element,
            boundary,
            maskRegions,
            MaskSource.manual,
          );
        case MaskContext.unmask:
          break; // Unmask suppresses auto-masking
        case MaskContext.none:
          // Auto-masking: check directive rules for text/image
          final renderObject = element.renderObject;
          if (renderObject != null) {
            final maskRegionInfo = _shouldMaskRenderObject(
              renderObject,
              boundary,
              currentViewportBounds,
            );
            if (maskRegionInfo != null) {
              maskRegions.add(maskRegionInfo);
            }
          }
      }
    }

    // ALWAYS continue traversal to children (traversal never stops early)
    // Using debugVisitOnstageChildren to automatically skip Offstage, hidden Overlays, and inactive IndexedStack children
    element.debugVisitOnstageChildren((child) {
      _traverseElementTree(
        child,
        boundary,
        maskRegions,
        traversalState: traversalState,
        maskContext: currentContext,
        tickerEnabled: currentTickerEnabled,
        viewportBounds: currentViewportBounds,
      );
    });
  }

  bool _hasUnsafeVisualState(Widget widget) {
    final widgetType = widget.runtimeType;
    final typeName = _widgetTypeNames.putIfAbsent(
      widgetType,
      widgetType.toString,
    );

    // Route transition detection.
    if (typeName == '_ModalScopeStatus') {
      try {
        final route = (widget as dynamic).route;
        if (route is ModalRoute) {
          final animationStatus = route.animation?.status;
          final secondaryStatus = route.secondaryAnimation?.status;
          return animationStatus == AnimationStatus.forward ||
              animationStatus == AnimationStatus.reverse ||
              secondaryStatus == AnimationStatus.forward ||
              secondaryStatus == AnimationStatus.reverse;
        }
      } catch (_) {
        return false;
      }
    }

    // StretchEffect is private Flutter API. A non-zero paint-only transform is
    // not represented by getTransformTo(), so its mask coordinates are unsafe.
    if (typeName == 'StretchEffect') {
      try {
        return (widget as dynamic).stretchStrength != 0.0;
      } catch (_) {
        return false;
      }
    }

    return false;
  }

  /// Add an element's bounds to mask rects
  void _addElementToMaskRects(
    Element element,
    RenderRepaintBoundary boundary,
    List<MaskRegionInfo> maskRects,
    MaskSource source,
  ) {
    final renderObject = element.renderObject;
    if (renderObject is RenderBox && renderObject.hasSize) {
      try {
        // Use same coordinate calculation as auto-masking to handle ScrollView
        final globalOffset = renderObject.localToGlobal(Offset.zero);
        final boundaryGlobalOffset = boundary.localToGlobal(Offset.zero);
        final offset = globalOffset - boundaryGlobalOffset;

        final bounds = offset & renderObject.size;

        // Validate bounds are within boundary (same validation as auto-masking)
        final boundaryBounds = Rect.fromLTWH(
          0,
          0,
          boundary.size.width,
          boundary.size.height,
        );

        if (!boundaryBounds.overlaps(bounds)) {
          return;
        }

        // Clip to boundary bounds
        final clippedBounds = bounds.intersect(boundaryBounds);

        maskRects.add(MaskRegionInfo(clippedBounds, source));
      } catch (_) {
        // Ignore elements that can't be positioned relative to boundary
      }
    }
  }

  /// Check if a RenderObject should be masked
  ///
  /// Returns the MaskRegionInfo to mask, or null if not masked
  MaskRegionInfo? _shouldMaskRenderObject(
    RenderObject node,
    RenderRepaintBoundary boundary,
    Rect?
    viewportBounds, // Cached viewport bounds from traversal (avoids tree walk)
  ) {
    if (node is! RenderBox) return null;

    // After is! check, node is promoted to RenderBox
    if (!node.hasSize) return null;

    // CRITICAL: Filter out widgets that aren't actually visible
    // This prevents masking widgets on inactive Navigator routes
    if (!node.attached) return null; // Not attached to render tree

    // Skip if paint bounds are empty (widget doesn't contribute to final render)
    // This filters out widgets that exist in the tree but are visually hidden
    // behind other widgets (z-order issue)
    if (node.paintBounds.isEmpty) return null;

    // Detect widget type
    WidgetType? widgetType;

    // PERFORMANCE: Check fast type checks first before expensive string operations
    // Check for text (any type of text rendering)
    // - RenderEditable: TextField, TextFormField (editable text)
    if (node is RenderEditable) {
      widgetType = WidgetType.text;
    } else if (node is RenderParagraph) {
      widgetType = WidgetType.text;
    } else if (node is RenderImage) {
      widgetType = WidgetType.image;
    }

    if (widgetType == null) return null;

    // Get bounds relative to the boundary's RENDERED position (viewport)
    // Use matrix transforms to correctly handle rotation, scaling, skewing, etc.
    Rect bounds;
    try {
      // Get the transformation matrix from this widget to the boundary
      // This handles all transforms (rotation, scale, skew) correctly
      final transform = node.getTransformTo(boundary);

      // Transform the paint bounds using the matrix
      // paintBounds includes the actual painted area (better than size for clipped content)
      // Result is already in boundary-relative coordinates
      bounds = MatrixUtils.transformRect(transform, node.paintBounds);
    } catch (_) {
      // Can't get transform to boundary, skip
      return null;
    }

    // Define boundary bounds (the visible area we're capturing)
    final boundaryBounds = Rect.fromLTWH(
      0,
      0,
      boundary.size.width,
      boundary.size.height,
    );

    // CRITICAL: Filter out widgets that are completely outside the visible boundary
    // This includes widgets on inactive Navigator routes, which are positioned offscreen.
    if (!boundaryBounds.overlaps(bounds)) {
      return null;
    }

    // Check if widget is inside a scrollable viewport and if so, verify it's within viewport bounds
    // This prevents masking items that are scrolled off-screen in ListViews, GridViews, etc.
    // viewportBounds is passed from tree traversal (cached - no tree walk needed!)
    if (viewportBounds != null) {
      // Widget is inside a scrollable - check if it's within the viewport
      if (!viewportBounds.overlaps(bounds)) {
        return null; // Scrolled completely out of view
      }
    }

    // Check if this widget should be masked based on directive
    if (directive.shouldMask(bounds, widgetType)) {
      // Clip mask bounds to boundary - only mask the portion that's actually visible
      var clippedBounds = bounds.intersect(boundaryBounds);

      // Also clip to viewport bounds if inside a scrollable (only mask visible portion)
      if (viewportBounds != null) {
        clippedBounds = clippedBounds.intersect(viewportBounds);
      }

      // CRITICAL: Filter out masks that don't have any actual visible area
      // This handles edge cases like content scrolled completely out of view
      if (clippedBounds.isEmpty ||
          clippedBounds.width <= 0 ||
          clippedBounds.height <= 0) {
        return null;
      }

      return MaskRegionInfo(clippedBounds, MaskSource.auto);
    }

    return null;
  }
}

class _MaskTraversalState {
  bool shouldSkipCapture = false;
}

/// Exception thrown when mask detection fails
class MaskDetectionException implements Exception {
  final String message;

  MaskDetectionException(this.message);

  @override
  String toString() => 'MaskDetectionException: $message';
}

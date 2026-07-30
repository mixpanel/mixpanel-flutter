import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../models/configuration.dart' show AutoMaskedView;
import '../../models/masking_directive.dart';
import '../../models/wireframe.dart';
import '../../models/wireframes_options.dart' show MaskDecision;
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

  /// Raw wireframe elements collected during the walk. Non-null only when
  /// `MaskDetector.collectWireframes` was true. Elements carry the initial
  /// mask decision from the detector; geometric leak prevention and user
  /// sensitive rules are applied downstream by `WireframeEmitter`.
  final List<WireframeElement>? rawWireframes;

  MaskDetectionResult({
    required this.maskRegions,
    this.shouldSkipCapture = false,
    this.rawWireframes,
  });
}

/// Detects widgets that should be masked in screenshots
class MaskDetector {
  /// Configuration for auto-masking
  final MaskingDirective directive;

  /// Whether to track unmask region bounds for debug overlay
  final bool trackUnmaskBounds;

  /// Whether to collect wireframe elements during the walk. When true, the
  /// result's `rawWireframes` field is populated with the detector's
  /// initial mask decision per element.
  final bool collectWireframes;

  MaskDetector({
    required this.directive,
    this.trackUnmaskBounds = false,
    this.collectWireframes = false,
  });

  /// Traverse widget tree and collect mask regions
  ///
  /// Returns MaskDetectionResult with regions and bounds snapshot, or throws on error
  MaskDetectionResult detectMaskRegions(RenderRepaintBoundary boundary) {
    final maskRegions = <MaskRegionInfo>[];
    final wireframes = collectWireframes ? <WireframeElement>[] : null;
    // Dedup wireframe emission by RenderObject identity. Non-RenderObjectElements
    // (Text, MixpanelMask, etc.) return the same descendant render object from
    // element.renderObject, so without this a single Text emits 2-3 duplicates.
    final wireframeVisited = collectWireframes
        ? Set<RenderObject>.identity()
        : null;
    bool shouldSkipCapture = false;

    try {
      // Find the element that owns this boundary
      final boundaryElement = _findElementForRenderObject(boundary);
      if (boundaryElement == null) {
        return MaskDetectionResult(maskRegions: [], rawWireframes: wireframes);
      }

      // Check for conditions that would cause mask coordinate mismatch
      shouldSkipCapture = _shouldSkipCapture(boundaryElement);

      // Traverse descendants and track TickerMode state to filter background routes
      _traverseElementTree(
        boundaryElement,
        boundary,
        maskRegions,
        wireframes: wireframes,
        wireframeVisited: wireframeVisited,
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
      shouldSkipCapture: shouldSkipCapture,
      rawWireframes: wireframes,
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
    required MaskContext maskContext,
    required bool tickerEnabled,
    Rect?
    viewportBounds, // Cached viewport bounds (detected once, reused for all children)
    List<WireframeElement>? wireframes,
    Set<RenderObject>? wireframeVisited,
    String? enclosingImageLabel,
    String?
    declaredText, // Developer-declared wireframe text handed down from an enclosing marker to its DIRECT child (one level only)
  }) {
    final widget = element.widget;

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

    // Track the nearest enclosing image accessibility label so a descendant
    // `RenderImage` can adopt it. The `Image` widget applies `semanticLabel`
    // by wrapping its `RawImage` in `Semantics(image: true, label: ...)` — the
    // label is NOT on `RenderImage` itself — so we thread it DOWN the walk
    // (never walking up). Gating on `image == true` targets image semantics
    // only, so a generic `Semantics(label:)` around other content doesn't leak
    // onto images. Cleared by a nested image-Semantics with an empty label.
    String? currentImageLabel = enclosingImageLabel;
    if (widget is Semantics && widget.properties.image == true) {
      final label = widget.properties.label;
      currentImageLabel = (label != null && label.isNotEmpty) ? label : null;
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

    // Developer-declared wireframe text rides on MixpanelMask/MixpanelUnmask
    // via their `wireframeText`. It is handed to the marker's DIRECT child (one
    // level only — unlike mask context, it does NOT cascade further down) so
    // the declared element carries the child's real role + bounds.
    //
    // When a marker declares text we suppress its OWN wireframe emission: a
    // marker is a `StatelessWidget` with no render object of its own, so
    // `element.renderObject` resolves to the child's render object. Letting the
    // marker collect would consume (and mark visited) that shared render object
    // first, and the direct child — which knows its true role (e.g. button) —
    // could never apply the declared text.
    final String? childDeclaredText = widget is MixpanelMask
        ? widget.wireframeText
        : widget is MixpanelUnmask
        ? widget.wireframeText
        : null;
    final bool declaresChildText = childDeclaredText != null;

    // Wireframe collection — piggyback on the same walk. Uses the same
    // MaskContext as masking. The detector's initial mask decision is
    // derived here; geometric leak prevention and user sensitive rules
    // are applied later by WireframeEmitter. `declaredText` (from an enclosing
    // declaring marker, i.e. this element is that marker's direct child) is
    // applied to this element's role + bounds.
    if (wireframes != null && wireframeVisited != null && !declaresChildText) {
      _collectWireframeElement(
        element,
        boundary,
        wireframes,
        maskContext: currentContext,
        visited: wireframeVisited,
        imageLabel: currentImageLabel,
        declaredText: declaredText,
      );
    }

    // ALWAYS continue traversal to children (traversal never stops early)
    // Using debugVisitOnstageChildren to automatically skip Offstage, hidden Overlays, and inactive IndexedStack children
    element.debugVisitOnstageChildren((child) {
      _traverseElementTree(
        child,
        boundary,
        maskRegions,
        maskContext: currentContext,
        tickerEnabled: currentTickerEnabled,
        viewportBounds: currentViewportBounds,
        wireframes: wireframes,
        wireframeVisited: wireframeVisited,
        enclosingImageLabel: currentImageLabel,
        // Only a declaring marker passes text down (to its direct child); every
        // other node passes null so declared text never cascades past one level.
        declaredText: childDeclaredText,
      );
    });
  }

  /// Detect conditions where mask coordinates would not match the visual output.
  ///
  /// Returns true if capture should be skipped. Currently detects:
  /// 1. Route transitions — both routes are onstage with TickerMode(enabled: true),
  ///    causing overlapping masks from outgoing and incoming routes.
  /// 2. Overscroll stretch — StretchEffect widget with non-zero stretchStrength
  ///    applies a paint-only transform not reflected in getTransformTo().
  bool _shouldSkipCapture(Element root) {
    bool skip = false;

    void visit(Element element) {
      if (skip) return;

      final widget = element.widget;

      // 1. Route transition detection
      if (widget.runtimeType.toString() == '_ModalScopeStatus') {
        try {
          final route = (widget as dynamic).route;
          if (route is ModalRoute) {
            final animStatus = route.animation?.status;
            final secondaryStatus = route.secondaryAnimation?.status;

            // Route is being pushed behind, popped, or pushed in
            if (animStatus == AnimationStatus.forward ||
                animStatus == AnimationStatus.reverse ||
                secondaryStatus == AnimationStatus.forward ||
                secondaryStatus == AnimationStatus.reverse) {
              skip = true;
              return;
            }
          }
        } catch (_) {
          // If dynamic access fails, continue scanning
        }
      }

      // 2. Overscroll stretch detection
      // StretchEffect is used by StretchingOverscrollIndicator but is not
      // publicly exported. When stretchStrength != 0, a paint-only transform
      // is active that getTransformTo() doesn't reflect, causing mask
      // coordinate mismatch.
      if (widget.runtimeType.toString() == 'StretchEffect') {
        try {
          if ((widget as dynamic).stretchStrength != 0.0) {
            skip = true;
            return;
          }
        } catch (_) {
          // If dynamic access fails, continue scanning
        }
      }

      element.visitChildren(visit);
    }

    root.visitChildren(visit);
    return skip;
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
    } else {
      // Only call toString() if type check failed (expensive operation)
      final typeName = node.runtimeType.toString();

      // - RenderParagraph: Text, RichText (non-editable text)
      if (typeName.contains('RenderParagraph')) {
        widgetType = WidgetType.text;
      }
      // Check for images (RenderImage)
      else if (typeName.contains('RenderImage')) {
        widgetType = WidgetType.image;
      }
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

  /// Widget type name substrings identifying button-like widgets. Detection
  /// is intentionally string-based to match the existing idiom in this file
  /// (see the RenderParagraph / RenderImage / RenderViewport checks) and to
  /// keep buttons opt-in for common Material/Cupertino types without pulling
  /// in a semantics tree walk.
  static const List<String> _buttonWidgetPatterns = [
    'ElevatedButton',
    'TextButton',
    'OutlinedButton',
    'FilledButton',
    'IconButton',
    'FloatingActionButton',
    'MaterialButton',
    'CupertinoButton',
    'RawMaterialButton',
  ];

  /// Collect at most one wireframe element for [element], with initial
  /// [MaskDecision] derived from [maskContext] plus widget type.
  ///
  /// Elements that don't map to a wireframe role (containers, layout
  /// widgets, etc.) contribute nothing here — but traversal continues into
  /// their children so descendants can still emit.
  void _collectWireframeElement(
    Element element,
    RenderRepaintBoundary boundary,
    List<WireframeElement> out, {
    required MaskContext maskContext,
    required Set<RenderObject> visited,
    String? imageLabel,
    String? declaredText,
  }) {
    final renderObject = element.renderObject;
    if (renderObject == null || visited.contains(renderObject)) return;

    // Developer-declared text (from an enclosing MixpanelMask/MixpanelUnmask
    // `wireframeText`) is applied to this element — the marker's direct child —
    // with the child's real role + bounds. Declared text is authored, not
    // scraped: it is emitted with `MaskDecision.none` and `declared: true`, so
    // downstream it bypasses the geometric strip (surviving even when the marker
    // masks the pixels) but still runs through user SensitiveRules.
    //
    // Input fields are exempt — RenderEditable security masking can never be
    // overridden — so they fall through to the normal input handling below.
    if (declaredText != null && renderObject is! RenderEditable) {
      final bounds = _boundaryRelativeBounds(renderObject, boundary);
      if (bounds == null) return;
      final WireframeRole role;
      if (_isButtonWidget(element.widget)) {
        role = WireframeRole.button;
        // Consume descendant paragraphs / nested buttons so the button's own
        // label doesn't re-emit as standalone elements — same as the normal
        // button path, but the declared text replaces the scraped label.
        _collectDescendantParagraphText(element, visited);
        _markNestedButtonsVisited(element, visited);
      } else {
        final typeName = renderObject.runtimeType.toString();
        role = typeName.contains('RenderImage')
            ? WireframeRole.image
            // RenderParagraph, custom-drawn content (CustomPaint/Canvas), or any
            // other opaque render object the developer explicitly labeled.
            : WireframeRole.text;
      }
      visited.add(renderObject);
      out.add(
        WireframeElement(
          role: role,
          text: declaredText,
          bounds: bounds,
          maskDecision: MaskDecision.none,
          declared: true,
        ),
      );
      return;
    }

    // Input fields — always masked, cannot be overridden.
    if (renderObject is RenderEditable) {
      final bounds = _boundaryRelativeBounds(renderObject, boundary);
      if (bounds == null) return;
      visited.add(renderObject);
      out.add(
        WireframeElement(
          role: WireframeRole.input,
          text: null,
          bounds: bounds,
          maskDecision: MaskDecision.textEntry,
        ),
      );
      return;
    }

    // Buttons — role identified by widget type name. Descendant paragraphs
    // are absorbed into the button label and marked visited so they don't
    // re-emit as standalone text elements. An icon-only button carries no
    // visible text, so when unmasked we fall back to an accessibility label
    // (tooltip / semanticLabel). The descendant walk always runs — even
    // when masked — so its paragraphs are consumed and never re-emit as
    // separate shells.
    if (_isButtonWidget(element.widget)) {
      final bounds = _boundaryRelativeBounds(renderObject, boundary);
      if (bounds == null) return;
      final decision = _wireframeDecision(
        role: WireframeRole.button,
        maskContext: maskContext,
      );
      final visibleLabel = _collectDescendantParagraphText(element, visited);
      final label = decision == MaskDecision.none
          ? (visibleLabel ?? _collectDescendantSemanticLabel(element))
          : null;
      visited.add(renderObject);
      // Composite buttons build on inner buttons (e.g. FloatingActionButton
      // wraps a RawMaterialButton). Mark those nested button render objects
      // visited so the ongoing top-down walk doesn't emit them as duplicate
      // shells now that textless shells are kept.
      _markNestedButtonsVisited(element, visited);
      out.add(
        WireframeElement(
          role: WireframeRole.button,
          text: label,
          bounds: bounds,
          maskDecision: decision,
        ),
      );
      return;
    }

    // Text — RenderParagraph.
    final typeName = renderObject.runtimeType.toString();
    if (typeName.contains('RenderParagraph')) {
      final bounds = _boundaryRelativeBounds(renderObject, boundary);
      if (bounds == null) return;
      final text = _extractParagraphText(renderObject);
      final decision = _wireframeDecision(
        role: WireframeRole.text,
        maskContext: maskContext,
      );
      visited.add(renderObject);
      out.add(
        WireframeElement(
          role: WireframeRole.text,
          text: decision == MaskDecision.none ? text : null,
          bounds: bounds,
          maskDecision: decision,
        ),
      );
      return;
    }

    // Image — RenderImage. The accessibility label comes from the enclosing
    // `Semantics(image: true, label: ...)` threaded down as [imageLabel] (the
    // `Image` widget puts the label there, not on `RenderImage`).
    if (typeName.contains('RenderImage')) {
      final bounds = _boundaryRelativeBounds(renderObject, boundary);
      if (bounds == null) return;
      final label = imageLabel;
      final decision = _wireframeDecision(
        role: WireframeRole.image,
        maskContext: maskContext,
      );
      visited.add(renderObject);
      out.add(
        WireframeElement(
          role: WireframeRole.image,
          text: decision == MaskDecision.none ? label : null,
          bounds: bounds,
          maskDecision: decision,
        ),
      );
      return;
    }
  }

  /// Compute bounds relative to the capture boundary. Returns null if the
  /// element has no size / not attached / doesn't overlap the boundary, or
  /// if the effective bounds are sub-pixel (nothing meaningful to emit).
  Rect? _boundaryRelativeBounds(
    RenderObject node,
    RenderRepaintBoundary boundary,
  ) {
    if (node is! RenderBox) return null;
    if (!node.hasSize || !node.attached) return null;
    try {
      final transform = node.getTransformTo(boundary);
      final bounds = MatrixUtils.transformRect(transform, node.paintBounds);
      final boundaryBounds = Rect.fromLTWH(
        0,
        0,
        boundary.size.width,
        boundary.size.height,
      );
      if (!boundaryBounds.overlaps(bounds)) return null;
      final clipped = bounds.intersect(boundaryBounds);
      if (clipped.width < 1 || clipped.height < 1) return null;
      return clipped;
    } catch (_) {
      return null;
    }
  }

  /// Initial mask decision for a wireframe element. Buttons/text/images
  /// inside a `MixpanelMask` subtree are `explicit`. Text/image widgets are
  /// further evaluated against `autoMaskTypes`. `MaskContext.unmask`
  /// cascades safety down — descendants use `none`.
  MaskDecision _wireframeDecision({
    required WireframeRole role,
    required MaskContext maskContext,
  }) {
    if (maskContext == MaskContext.mask) return MaskDecision.explicit;
    if (maskContext == MaskContext.unmask) return MaskDecision.none;
    // MaskContext.none — apply auto-mask rules.
    switch (role) {
      case WireframeRole.text:
        return directive.autoMaskTypes.contains(AutoMaskedView.text)
            ? MaskDecision.auto
            : MaskDecision.none;
      case WireframeRole.image:
        return directive.autoMaskTypes.contains(AutoMaskedView.image)
            ? MaskDecision.auto
            : MaskDecision.none;
      case WireframeRole.button:
      case WireframeRole.input:
        return MaskDecision.none;
    }
  }

  bool _isButtonWidget(Widget widget) {
    final name = widget.runtimeType.toString();
    for (final pattern in _buttonWidgetPatterns) {
      if (name.contains(pattern)) return true;
    }
    return false;
  }

  /// Walk descendants of [buttonElement] and join text from any
  /// `RenderParagraph` found. Skips `RenderEditable` so a masked text field
  /// nested in a button never leaks into the button's label. Marks each
  /// consumed paragraph in [visited] so it doesn't re-emit as a standalone
  /// text element.
  ///
  /// Bare icon glyphs (an [Icon] renders as a `RenderParagraph` holding a
  /// single private-use codepoint) are still consumed and marked visited —
  /// so they never re-emit — but are NOT added to the label, since a glyph
  /// is not human-readable text. Such buttons fall back to
  /// [_collectDescendantSemanticLabel].
  String? _collectDescendantParagraphText(
    Element buttonElement,
    Set<RenderObject> visited,
  ) {
    final buffer = <String>[];
    void visit(Element child) {
      final renderObject = child.renderObject;
      if (renderObject != null &&
          renderObject is! RenderEditable &&
          !visited.contains(renderObject)) {
        final typeName = renderObject.runtimeType.toString();
        if (typeName.contains('RenderParagraph')) {
          visited.add(renderObject);
          final text = _extractParagraphText(renderObject);
          if (text.isNotEmpty && wireframeTextIsHumanReadable(text)) {
            buffer.add(text);
          }
        }
      }
      child.debugVisitOnstageChildren(visit);
    }

    buttonElement.debugVisitOnstageChildren(visit);
    if (buffer.isEmpty) return null;
    return buffer.join(' ');
  }

  /// Best-effort human-readable label for an icon-only [buttonElement],
  /// pulled from accessibility metadata in its subtree. Priority order
  /// (first non-empty match in traversal order wins): a `Tooltip` message,
  /// an [Icon]/[ImageIcon] `semanticLabel`, then a `Semantics(label:)`.
  /// Returns null when none is set.
  ///
  /// Only descendants are inspected — never walks up — consistent with the
  /// traversal performance rules. Callers must gate this on an unmasked
  /// decision so a masked button stays textless. `Tooltip` is matched by
  /// runtime-type name (it lives in the Material library, which this file
  /// intentionally does not import) with a dynamic property read.
  String? _collectDescendantSemanticLabel(Element buttonElement) {
    String? found;
    void visit(Element child) {
      if (found != null) return;
      final widget = child.widget;
      if (widget is Icon) {
        final label = widget.semanticLabel;
        if (label != null && label.isNotEmpty) {
          found = label;
          return;
        }
      } else if (widget is ImageIcon) {
        final label = widget.semanticLabel;
        if (label != null && label.isNotEmpty) {
          found = label;
          return;
        }
      } else if (widget is Semantics) {
        final label = widget.properties.label;
        if (label != null && label.isNotEmpty) {
          found = label;
          return;
        }
      } else if (widget.runtimeType.toString() == 'Tooltip') {
        try {
          final message = (widget as dynamic).message as String?;
          if (message != null && message.isNotEmpty) {
            found = message;
            return;
          }
        } catch (_) {
          // Not the Material Tooltip we expected — ignore and keep walking.
        }
      }
      child.debugVisitOnstageChildren(visit);
    }

    buttonElement.debugVisitOnstageChildren(visit);
    return found;
  }

  /// Mark the render objects of any nested button-like widgets in
  /// [buttonElement]'s subtree as visited so the ongoing top-down traversal
  /// skips them. Composite buttons (e.g. `FloatingActionButton` →
  /// `RawMaterialButton`) are built from inner button widgets that would
  /// otherwise emit as duplicate shells now that textless shells are kept.
  /// Descendants only — never walks up.
  void _markNestedButtonsVisited(
    Element buttonElement,
    Set<RenderObject> visited,
  ) {
    void visit(Element child) {
      if (_isButtonWidget(child.widget)) {
        final renderObject = child.renderObject;
        if (renderObject != null) visited.add(renderObject);
      }
      child.debugVisitOnstageChildren(visit);
    }

    buttonElement.debugVisitOnstageChildren(visit);
  }

  String _extractParagraphText(RenderObject node) {
    try {
      final text = (node as dynamic).text as InlineSpan?;
      return text?.toPlainText() ?? '';
    } catch (_) {
      return '';
    }
  }
}

/// Exception thrown when mask detection fails
class MaskDetectionException implements Exception {
  final String message;

  MaskDetectionException(this.message);

  @override
  String toString() => 'MaskDetectionException: $message';
}

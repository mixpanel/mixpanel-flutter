import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'widget_classification.dart';
import 'traversal_limits.dart';

enum ResponseChange { unchanged, changed, unknown }

/// Ephemeral comparison state. Never serialize, log, persist, or attach this
/// hash to ClickEvent. Unknown coverage is null, not an empty snapshot.
class ResponseSnapshot {
  const ResponseSnapshot(this._hash);
  final int _hash;
  bool differsFrom(ResponseSnapshot other) => _hash != other._hash;
  ResponseChange compare(ResponseSnapshot? current) => current == null
      ? ResponseChange.unknown
      : differsFrom(current)
          ? ResponseChange.changed
          : ResponseChange.unchanged;

  static ResponseSnapshot? capture(Element root, Rect viewport) {
    return _SnapshotBuilder(viewport).capture(root);
  }
}

/// One traversal owns its digest, geometry cache and budget.
class _SnapshotBuilder {
  _SnapshotBuilder(this.viewport);
  final Rect viewport;
  var count = 0;
  var hash = 17;
  // Keep the rolling digest bounded; it is transient comparison state only.
  // Cache actual parent paint transforms, preserving scroll/transform behavior.
  final transforms = <RenderObject, Matrix4>{};
  Matrix4 globalTransform(RenderObject object) {
    final cached = transforms[object];
    if (cached != null) return cached;
    final parent = object.parent;
    // getTransformTo(null) excludes the root's physical-pixel transform.
    // Keep snapshots in the same logical coordinate space as the viewport.
    final matrix = parent == null || identical(parent, object.owner?.rootNode)
        ? Matrix4.identity()
        : (globalTransform(parent).clone()
          ..multiply(object.getTransformTo(parent)));
    transforms[object] = matrix;
    return matrix;
  }

  Rect? bounds(RenderObject? object) {
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      return null;
    }
    return MatrixUtils.transformRect(
        globalTransform(object), Offset.zero & object.size);
  }

  void add(Object? value) => hash = (31 * hash + value.hashCode) & 0x3fffffff;
  void visit(Element element, int depth, [Widget? materialChild]) {
    if (!element.mounted) throw StateError('detached');
    final w = element.widget;
    if (identical(w, materialChild)) materialChild = null;
    // Material builds border painters around its public child. These are
    // control feedback; app painters inside that child remain unsupported.
    if (w is Material) materialChild = w.child;
    if (hidden(w)) return;
    final render = element is RenderObjectElement ? element.renderObject : null;
    final renderBounds = bounds(render);
    if (renderBounds != null) {
      if (!renderBounds.isFinite) throw StateError('geometry');
      // Do not prune Element descendants based on this render box: a
      // zero-sized/offscreen OverlayPortal host can have visible children
      // attached elsewhere in the render tree.
    }
    if (++count > maxNodes || depth > maxDepth) {
      reportTraversalLimit();
      throw StateError('limit');
    }
    checkCoverage(element, w, render, renderBounds, materialChild);
    if (isFeedbackControl(w)) {
      addControlState(element, w);
      // Never descend into editable text, its decoration, cursor or controller.
      // Other feedback controls also have paint-only animation internals.
      return;
    }
    // Only meaningful public widgets contribute. Framework paint/rebuild
    // machinery and Ink ripple/highlight state are intentionally omitted.
    final meaningful = w is Text ||
        w is RichText ||
        w is Image ||
        w is Icon ||
        isButton(w) ||
        w is Row ||
        w is Column ||
        w is Stack ||
        w is ColoredBox ||
        w is DecoratedBox ||
        w is RawImage;
    if (meaningful) {
      final object = render ?? element.findRenderObject();
      final rect = identical(object, render) ? renderBounds : bounds(object);
      if (rect != null && !rect.overlaps(viewport)) {
        element
            .visitChildren((child) => visit(child, depth + 1, materialChild));
        return;
      }
      add(typeName(w));
      if (rect != null) {
        add(rect.left.round());
        add(rect.top.round());
        add(rect.width.round());
        add(rect.height.round());
      }
      addContent(w, object);
    }
    element.visitChildren((child) => visit(child, depth + 1, materialChild));
  }

  void checkCoverage(Element element, Widget w, RenderObject? render,
      Rect? renderBounds, Widget? materialChild) {
    // A Flutter tree cannot prove the absence of a response in these surfaces.
    // Suppress dead detection for the view, including responses elsewhere in
    // that view, rather than treating unchanged Flutter state as success/failure.
    if (w is AndroidView ||
        w is UiKitView ||
        w is HtmlElementView ||
        w is PlatformViewLink ||
        w is Texture ||
        (w is CustomPaint &&
            materialChild == null &&
            ((w.painter != null && w.painter is! BannerPainter) ||
                (w.foregroundPainter != null &&
                    w.foregroundPainter is! BannerPainter)))) {
      // Platform-view widgets can be Stateful/StatelessElements, so their
      // render object is not necessarily the current Element's own object.
      final surface = render ?? element.findRenderObject();
      final surfaceBounds =
          identical(surface, render) ? renderBounds : bounds(surface);
      // Only proven offscreen surfaces are harmless. Missing or invalid
      // geometry cannot establish visibility and keeps the view fail-closed.
      if (surfaceBounds == null ||
          !surfaceBounds.isFinite ||
          surfaceBounds.isEmpty ||
          surfaceBounds.overlaps(viewport)) {
        throw StateError('unsupported response surface');
      }
      // Keep visiting: Element descendants may render elsewhere via a portal.
    }
  }

  void addControlState(Element element, Widget w) {
    add(typeName(w));
    if (w is Switch) add(w.value);
    if (w is CupertinoSwitch) add(w.value);
    if (w is Checkbox) add(w.value);
    // Flutter 3.19 has no RadioGroup API. RenderSemanticsAnnotations
    // exposes the effective selected state on both legacy and modern Radio.
    if (w is Radio) {
      bool? checked;
      void readChecked(Element child) {
        if (checked != null) return;
        if (++count > maxNodes) {
          reportTraversalLimit();
          throw StateError('limit');
        }
        final widget = child.widget;
        if (widget is Semantics && widget.properties.checked != null) {
          checked = widget.properties.checked;
          return;
        }
        child.visitChildren(readChecked);
      }

      element.visitChildren(readChecked);
      // Unknown radio coverage suppresses dead detection for the whole
      // view, since a response anywhere in that view cancels a dead click.
      if (checked == null) throw StateError('unknown radio state');
      add(checked);
    }
    if (w is Slider) add(w.value);
    if (w is RangeSlider) {
      add(w.values.start);
      add(w.values.end);
    }
    if (w is CupertinoSlider) add(w.value);
  }

  void addContent(Widget w, RenderObject? object) {
    // Content contributes only to this short-lived, in-memory digest. No
    // string, span.toString(), key or diagnostic map leaves this method.
    if (w is Text) {
      add(w.data ?? w.textSpan?.toPlainText(includeSemanticsLabels: false));
    }
    if (w is RichText) {
      add(w.text.toPlainText(includeSemanticsLabels: false));
    }
    if (w is Text) add(w.style);
    if (w is RichText) add(w.text.style);
    if (w is ColoredBox) add(w.color);
    if (w is DecoratedBox) add(w.decoration);
    if (w is RawImage) add(identityHashCode(w.image));
    if (w is Icon) {
      add(w.icon?.codePoint);
      add(w.color);
      add(w.size);
    }
    if (w is Image) {
      if (object is RenderImage) add(identityHashCode(object.image));
    }
    if (isButton(w)) add(deadEligible(w));
  }

  ResponseSnapshot? capture(Element root) {
    try {
      if (!root.mounted || viewport.isEmpty) return null;
      visit(root, 0);
      return ResponseSnapshot(hash);
    } catch (_) {
      return null;
    }
  }
}

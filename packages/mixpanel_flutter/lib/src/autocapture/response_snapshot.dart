import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'target_resolver.dart';

/// Ephemeral comparison state. Never serialize, log, persist, or attach this
/// hash to ClickEvent. Unknown coverage is null, not an empty snapshot.
class ResponseSnapshot {
  const ResponseSnapshot(this._hash);
  final int _hash;
  bool differsFrom(ResponseSnapshot other) => _hash != other._hash;

  static ResponseSnapshot? capture(Element root, Rect viewport) {
    var count = 0;
    var hash = 17;
    void add(Object? value) => hash = (31 * hash + value.hashCode) & 0x3fffffff;
    void visit(Element element, int depth, [Widget? materialChild]) {
      if (++count > TargetResolver.maxNodes ||
          depth > TargetResolver.maxDepth) {
        throw StateError('limit');
      }
      if (!element.mounted) throw StateError('detached');
      final w = element.widget;
      if (identical(w, materialChild)) materialChild = null;
      // Material builds border painters around its public child. These are
      // control feedback; app painters inside that child remain unsupported.
      if (w is Material) materialChild = w.child;
      if (TargetResolver.hidden(w)) return;
      final render =
          element is RenderObjectElement ? element.renderObject : null;
      if (render is RenderBox && render.attached && render.hasSize) {
        final rect = MatrixUtils.transformRect(
            render.getTransformTo(null), Offset.zero & render.size);
        if (!rect.isFinite) throw StateError('geometry');
        if (!rect.overlaps(viewport)) return;
      }
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
        throw StateError('unsupported response surface');
      }
      if (TargetResolver.isFeedbackControl(w)) {
        add(TargetResolver.typeName(w));
        if (w is Switch) add(w.value);
        if (w is CupertinoSwitch) add(w.value);
        if (w is Checkbox) add(w.value);
        if (w is Radio) add(w.value == w.groupValue);
        if (w is Slider) add(w.value);
        if (w is RangeSlider) {
          add(w.values.start);
          add(w.values.end);
        }
        if (w is CupertinoSlider) add(w.value);
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
          TargetResolver.isButton(w) ||
          w is Row ||
          w is Column ||
          w is Stack ||
          w is ColoredBox ||
          w is DecoratedBox ||
          w is RawImage;
      if (meaningful) {
        add(TargetResolver.typeName(w));
        final object = element.findRenderObject();
        if (object is RenderBox && object.attached && object.hasSize) {
          final rect = MatrixUtils.transformRect(
              object.getTransformTo(null), Offset.zero & object.size);
          add(rect.left.round());
          add(rect.top.round());
          add(rect.width.round());
          add(rect.height.round());
        }
        // Content contributes only to this short-lived, in-memory digest. No
        // string, span.toString(), key or diagnostic map leaves this method.
        if (w is Text)
          add(w.data ?? w.textSpan?.toPlainText(includeSemanticsLabels: false));
        if (w is RichText)
          add(w.text.toPlainText(includeSemanticsLabels: false));
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
          final object = element.findRenderObject();
          if (object is RenderImage) add(identityHashCode(object.image));
        }
        if (TargetResolver.isButton(w)) add(TargetResolver.deadEligible(w));
      }
      element.visitChildren((child) => visit(child, depth + 1, materialChild));
    }

    try {
      if (!root.mounted || viewport.isEmpty) return null;
      visit(root, 0);
      return ResponseSnapshot(hash);
    } catch (_) {
      return null;
    }
  }
}

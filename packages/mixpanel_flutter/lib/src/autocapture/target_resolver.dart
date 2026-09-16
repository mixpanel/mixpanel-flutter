import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'click_event.dart';

class CaptureTarget {
  const CaptureTarget(this.element, this.event, this.deadEligible);
  final Element element;
  final ClickEvent event;
  final bool deadEligible;
}

/// Bounded public Element traversal, never debugCreator/debugSemantics.
class TargetResolver {
  static const maxNodes = 2000;
  static const maxDepth = 512;

  CaptureTarget? resolve(Element root, PointerEvent pointer) {
    try {
      if (!root.mounted) return null;
      final owners = <HitTestTarget, Element>{};
      var count = 0;
      void visit(Element element, int depth) {
        if (++count > maxNodes || depth > maxDepth) throw StateError('limit');
        if (!element.mounted || hidden(element.widget)) return;
        if (element is RenderObjectElement)
          owners[element.renderObject] = element;
        element.visitChildren((child) => visit(child, depth + 1));
      }

      visit(root, 0);
      final hits = HitTestResult();
      WidgetsBinding.instance
          .hitTestInView(hits, pointer.position, pointer.viewId);
      Element? leaf;
      for (final hit in hits.path) {
        leaf = owners[hit.target];
        if (leaf != null) break;
      }
      if (leaf == null || identical(leaf, root)) return null;
      final path = <Element>[leaf];
      leaf.visitAncestorElements((parent) {
        if (identical(parent, root) || path.length >= maxDepth) return false;
        path.add(parent);
        return true;
      });
      Element? selected;
      var inkOwner = false;
      bool internalTo(Widget? child) {
        if (selected == null) return true;
        final boundary = path.indexWhere((e) => identical(e.widget, child));
        return boundary >= 0 && path.indexOf(selected) > boundary;
      }

      for (final element in path) {
        final w = element.widget;
        if (isFeedbackControl(w)) {
          selected = element;
          break;
        }
        if (w is GestureDetector && hasTap(w)) {
          if (selected != null) break;
          selected = element;
        } else if (w is InkResponse) {
          if (inkOwner) break; // A nested InkWell owns its own interaction.
          if (internalTo(w.child)) {
            selected = element;
            inkOwner = true;
          }
        } else if (isButton(w)) {
          // Promote a button's internal InkWell to its public control. A custom
          // nested GestureDetector with its own action keeps its identity.
          final child = w is ButtonStyleButton
              ? w.child
              : w is CupertinoButton
                  ? w.child
                  : w is IconButton
                      ? w.icon
                      : null;
          if (internalTo(child)) selected = element;
          break;
        }
      }
      selected ??= path.firstWhere(
          (element) =>
              element.widget is Text ||
              element.widget is RichText ||
              element.widget is Image ||
              element.widget is Icon,
          orElse: () => leaf!);
      final selectedIndex = path.indexOf(selected);
      final ancestors = path.skip(selectedIndex).toList();
      String? identifier;
      // Only semantic wrappers at/above the selected owner can name it. Never
      // use a descendant label/ID or cross another actionable ancestor.
      for (final element in ancestors.take(11)) {
        if (!identical(element, selected) && isTarget(element.widget)) break;
        final w = element.widget;
        if (w is Semantics) {
          final value = w.properties.identifier;
          if (value != null && value.trim().isNotEmpty && value.length <= 256) {
            identifier = value;
            break;
          }
        }
      }
      final tag = typeName(selected.widget);
      final hierarchy =
          ancestors.take(5).map((e) => typeName(e.widget)).join(' > ');
      final structural = <String>[];
      for (var i = selectedIndex;
          i < path.length && structural.length < maxDepth;
          i++) {
        var sibling = 0;
        if (i + 1 < path.length) {
          var index = 0;
          path[i + 1].visitChildren((child) {
            if (identical(child, path[i])) sibling = index;
            index++;
          });
        }
        structural.add('${typeName(path[i].widget)}[$sibling]');
      }
      final eligible = deadEligible(selected.widget) &&
          !ancestors.any((e) => isFeedbackControl(e.widget));
      return CaptureTarget(
          selected,
          ClickEvent(
            x: pointer.position.dx,
            y: pointer.position.dy,
            elementId:
                identifier ?? '${tag}_${stableHash(structural.join('/'))}',
            tagName: tag,
            role: role(selected.widget),
            elements: hierarchy,
          ),
          eligible);
    } catch (_) {
      return null; // Missing/over-budget ownership is never fabricated.
    }
  }

  static bool hidden(Widget w) =>
      (w is Offstage && w.offstage) ||
      (w is Visibility && !w.visible) ||
      (w is Opacity && w.opacity <= 0);

  static bool hasTap(GestureDetector w) =>
      w.onTap != null || w.onTapUp != null || w.onTapDown != null;
  static bool isButton(Widget w) =>
      w is ButtonStyleButton || w is IconButton || w is CupertinoButton;
  static bool isTarget(Widget w) =>
      isButton(w) ||
      isFeedbackControl(w) ||
      w is InkResponse ||
      (w is GestureDetector && hasTap(w));
  static bool isFeedbackControl(Widget w) =>
      w is EditableText ||
      w is TextField ||
      w is CupertinoTextField ||
      w is Switch ||
      w is CupertinoSwitch ||
      w is Checkbox ||
      w is Radio ||
      w is Slider ||
      w is RangeSlider ||
      w is CupertinoSlider ||
      w is CupertinoPicker ||
      w is CupertinoDatePicker ||
      w is DropdownButton ||
      w is CheckboxListTile ||
      w is SwitchListTile ||
      w is RadioListTile;

  static bool deadEligible(Widget w) {
    if (isFeedbackControl(w)) return false;
    if (w is ButtonStyleButton) return w.onPressed != null;
    if (w is IconButton) return w.onPressed != null;
    if (w is CupertinoButton) return w.onPressed != null;
    if (w is InkResponse) return w.onTap != null;
    if (w is GestureDetector) return w.onTap != null || w.onTapUp != null;
    return false;
  }

  static String? role(Widget w) {
    if (isButton(w) || w is InkResponse || w is GestureDetector)
      return 'Button';
    if (w is EditableText || w is TextField || w is CupertinoTextField)
      return 'TextField';
    if (w is Switch || w is CupertinoSwitch || w is SwitchListTile)
      return 'Switch';
    if (w is Checkbox || w is CheckboxListTile) return 'Checkbox';
    if (w is Radio || w is RadioListTile) return 'Radio';
    if (w is Slider || w is CupertinoSlider || w is RangeSlider)
      return 'Slider';
    if (w is Text || w is RichText) return 'Text';
    if (w is Image || w is Icon) return 'Image';
    return null;
  }

  /// Canonical names survive obfuscation and never stringify arbitrary widgets.
  static String typeName(Widget w) {
    if (w is ElevatedButton) return 'ElevatedButton';
    if (w is TextButton) return 'TextButton';
    if (w is OutlinedButton) return 'OutlinedButton';
    if (w is FilledButton) return 'FilledButton';
    if (w is IconButton) return 'IconButton';
    if (w is CupertinoButton) return 'CupertinoButton';
    if (w is InkWell) return 'InkWell';
    if (w is InkResponse) return 'InkResponse';
    if (w is GestureDetector) return 'GestureDetector';
    if (w is Semantics) return 'Semantics';
    if (w is Text) return 'Text';
    if (w is RichText) return 'RichText';
    if (w is Icon) return 'Icon';
    if (w is Image) return 'Image';
    if (w is Row) return 'Row';
    if (w is Column) return 'Column';
    if (w is Stack) return 'Stack';
    if (w is Padding) return 'Padding';
    if (w is Container) return 'Container';
    if (w is SizedBox) return 'SizedBox';
    if (w is Scaffold) return 'Scaffold';
    if (isFeedbackControl(w)) return role(w) ?? 'Picker';
    return 'Widget';
  }

  static String stableHash(String value) {
    var hash = 2166136261;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      // Split FNV multiplication so intermediates fit JS's exact integer range.
      hash = (hash * 0x193 + ((hash & 0xff) << 24)) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

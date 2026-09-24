import 'dart:convert';
import 'package:flutter/rendering.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'click_event.dart';
import 'widget_classification.dart';
import 'traversal_limits.dart';

class CaptureTarget {
  const CaptureTarget(this.element, this.event, this.deadEligible);
  final Element element;
  final ClickEvent event;
  final bool deadEligible;
}

/// Bounded public Element traversal, never debugCreator/debugSemantics.
class TargetResolver {
  CaptureTarget? resolve(Element root, PointerEvent pointer) {
    try {
      if (!root.mounted) return null;
      final leaf = _findHitOwner(root, pointer);
      if (leaf == null || identical(leaf, root)) return null;
      final path = <Element>[leaf];
      leaf.visitAncestorElements((parent) {
        if (identical(parent, root) || path.length >= maxDepth) return false;
        path.add(parent);
        return true;
      });
      final selected = _selectOwner(path);
      final selectedIndex = path.indexOf(selected);
      final ancestors = path.skip(selectedIndex).toList();
      final identifier = _explicitIdentifier(selected, ancestors);
      final tag = typeName(selected.widget);
      final hierarchy =
          ancestors.take(5).map((e) => typeName(e.widget)).join(' > ');
      final structural = _structuralPath(path, selectedIndex);
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

  Element? _findHitOwner(Element root, PointerEvent pointer) {
    final hits = HitTestResult();
    WidgetsBinding.instance
        .hitTestInView(hits, pointer.position, pointer.viewId);
    final hitTargets = hits.path.map((hit) => hit.target).toSet();
    // Render ancestry provides a fast path, but OverlayPortal can attach
    // element descendants to a different render parent. Verify ownership
    // of the deepest render hit before trusting this pruned walk.
    final ancestry = <RenderObject>{};
    for (final target in hitTargets) {
      if (target is! RenderObject) continue;
      RenderObject? current = target;
      while (current != null && ancestry.add(current)) {
        current = current.parent;
      }
    }
    final owners = <HitTestTarget, Element>{};
    var count = 0;
    void visit(Element element, int depth, {required bool prune}) {
      if (!element.mounted || hidden(element.widget)) return;
      if (prune &&
          element is RenderObjectElement &&
          !ancestry.contains(element.renderObject)) {
        return;
      }
      if (++count > maxNodes || depth > maxDepth) {
        reportTraversalLimit();
        throw StateError('limit');
      }
      if (element is RenderObjectElement &&
          hitTargets.contains(element.renderObject)) {
        owners[element.renderObject] = element;
      }
      element.visitChildren((child) => visit(child, depth + 1, prune: prune));
    }

    final renderHits = hits.path.where((hit) => hit.target is RenderObject);
    if (renderHits.isEmpty) return null;
    final deepest = renderHits.first.target;
    visit(root, 0, prune: true);
    if (!owners.containsKey(deepest)) {
      // A bounded slow path resolves portals without making ordinary taps
      // scan unrelated trees. Each pass has its own bounded visit budget.
      owners.clear();
      count = 0;
      visit(root, 0, prune: false);
    }
    return owners[deepest];
  }

  Element _selectOwner(List<Element> path) {
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
        orElse: () => path.first);
    return selected;
  }

  String? _explicitIdentifier(Element selected, List<Element> ancestors) {
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
    return identifier;
  }

  List<String> _structuralPath(List<Element> path, int selectedIndex) {
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
    return structural;
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

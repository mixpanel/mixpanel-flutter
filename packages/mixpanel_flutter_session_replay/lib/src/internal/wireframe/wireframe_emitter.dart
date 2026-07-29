import 'dart:ui';

import '../../models/masking_directive.dart';
import '../../models/session_event.dart';
import '../../models/wireframe.dart';
import '../../models/wireframes_options.dart';
import '../logger.dart';

/// Post-processes raw wireframe elements (from the [MaskDetector] walk)
/// by applying geometric leak prevention and user rules, then truncation,
/// noise-drop and dedup, invokes the optional debug callback, and returns
/// a [WireframePayload] ready to enqueue.
///
/// One instance per SDK lifetime; dedup state is per-emitter (not per
/// session).
class WireframeEmitter {
  WireframeEmitter({
    required this.sensitiveRules,
    required this.debugEmitter,
    required MixpanelLogger logger,
  }) : _logger = logger;

  final List<SensitiveRule> sensitiveRules;
  final void Function(WireframeSnapshot)? debugEmitter;
  final MixpanelLogger _logger;

  // Dedup state: keyed by (elementsHash, maskHash). Same-hash consecutive
  // emits are dropped so static screens don't spam events.
  int? _lastElementsHash;
  int? _lastMaskHash;

  /// Process raw elements through the pipeline. Returns null when the frame
  /// deduped against the previous emit (identical elements AND identical
  /// mask regions).
  WireframePayload? emit({
    required List<WireframeElement> rawElements,
    required List<MaskRegionInfo> maskRegions,
    required Size viewport,
    required DateTime timestamp,
  }) {
    // Geometric masking → user rules → truncation → noise-drop, per element.
    final processed = rawElements
        .map((el) => _applyGeometricMasking(el, maskRegions))
        .map(_applyRules)
        .map(_truncate)
        .where(_isMeaningful)
        .toList(growable: false);

    // Nothing meaningful survived; skip emit rather than shipping empty payload.
    if (processed.isEmpty) return null;

    // Dedup check against previous emit. Both must be unchanged to skip.
    final elementsHash = Object.hashAll(processed);
    final maskHash = Object.hashAll(maskRegions);
    if (_lastElementsHash == elementsHash && _lastMaskHash == maskHash) {
      return null;
    }
    _lastElementsHash = elementsHash;
    _lastMaskHash = maskHash;

    final payload = WireframePayload(
      viewportWidth: viewport.width.round(),
      viewportHeight: viewport.height.round(),
      elements: processed,
    );

    _fireDebugCallback(payload, timestamp);
    return payload;
  }

  /// Geometric leak prevention. Only runs on elements whose text survived
  /// the mask detector (i.e. [MaskDecision.none]). Reuses the same
  /// [MaskRegionInfo] list the screenshot painter draws.
  WireframeElement _applyGeometricMasking(
    WireframeElement el,
    List<MaskRegionInfo> maskRegions,
  ) {
    if (el.maskDecision != MaskDecision.none) return el;
    for (final region in maskRegions) {
      if (region.bounds.overlaps(el.bounds)) {
        return el.copyWith(
          clearText: true,
          maskDecision: MaskDecision.geometric,
        );
      }
    }
    return el;
  }

  /// User sensitive rules, in declared order. StripRule short-circuits;
  /// RedactRule rewrites in place and the next rule sees the rewritten value.
  WireframeElement _applyRules(WireframeElement el) {
    if (el.maskDecision != MaskDecision.none) return el;
    final originalText = el.text;
    if (originalText == null || originalText.isEmpty) return el;

    var current = originalText;
    var redacted = false;
    for (final rule in sensitiveRules) {
      switch (rule) {
        case StripRule(text: final needle):
          if (_containsIgnoreCase(current, needle)) {
            return el.copyWith(
              clearText: true,
              maskDecision: MaskDecision.ruleStrip,
            );
          }
        case StripRegexRule(:final regex):
          if (regex.hasMatch(current)) {
            return el.copyWith(
              clearText: true,
              maskDecision: MaskDecision.ruleStrip,
            );
          }
        case RedactRule(text: final needle, :final replacement):
          final replaced = _replaceAllIgnoreCase(current, needle, replacement);
          if (replaced != current) {
            current = replaced;
            redacted = true;
          }
        case RedactRegexRule(:final regex, :final replacement):
          if (regex.hasMatch(current)) {
            current = current.replaceAll(regex, replacement);
            redacted = true;
          }
      }
    }

    if (redacted) {
      return el.copyWith(text: current, maskDecision: MaskDecision.ruleRedact);
    }
    return el;
  }

  /// True if [el] carries information the AI or a human reviewer can't
  /// already glean from the accompanying screenshot. Elements with any
  /// mask decision other than [MaskDecision.none] always qualify — the
  /// decision itself explains a masked area. Otherwise, the element must
  /// carry at least one non-glyph character of text; a bare `role`+`bounds`
  /// entry (e.g. an icon-only button rendered as a private-use codepoint
  /// or an image with no semantic label) adds nothing beyond what's
  /// visible in the screenshot.
  static bool _isMeaningful(WireframeElement el) {
    if (el.maskDecision != MaskDecision.none) return true;
    final text = el.text;
    if (text == null || text.isEmpty) return false;
    return _hasNonGlyphChar(text);
  }

  /// True if [text] contains at least one character outside the Unicode
  /// private-use area (U+E000–U+F8FF), where icon fonts live.
  static bool _hasNonGlyphChar(String text) {
    for (final rune in text.runes) {
      if (rune < 0xE000 || rune > 0xF8FF) return true;
    }
    return false;
  }

  /// Truncate long text to [WireframeConstants.maxTextLength] chars plus
  /// [WireframeConstants.ellipsis]. Applied last so rule-rewrites are
  /// visible in the truncated output.
  WireframeElement _truncate(WireframeElement el) {
    final text = el.text;
    if (text == null || text.length <= WireframeConstants.maxTextLength) {
      return el;
    }
    final truncated =
        text.substring(0, WireframeConstants.maxTextLength) +
        WireframeConstants.ellipsis;
    return el.copyWith(text: truncated);
  }

  void _fireDebugCallback(WireframePayload payload, DateTime timestamp) {
    final callback = debugEmitter;
    if (callback == null) return;
    try {
      final snapshot = WireframeSnapshot(
        timestamp: timestamp.millisecondsSinceEpoch,
        viewport: [payload.viewportWidth, payload.viewportHeight],
        elements: payload.elements
            .map(
              (el) => WireframeSnapshotElement(
                role: el.role.wireName,
                text: el.text,
                bounds: [
                  el.bounds.left.round(),
                  el.bounds.top.round(),
                  el.bounds.width.round(),
                  el.bounds.height.round(),
                ],
                maskDecision: el.maskDecision,
              ),
            )
            .toList(growable: false),
      );
      callback(snapshot);
    } catch (e) {
      _logger.warning('Wireframe debug callback threw: $e', tag: 'wireframes');
    }
  }

  static bool _containsIgnoreCase(String haystack, String needle) {
    if (needle.isEmpty) return false;
    return haystack.toLowerCase().contains(needle.toLowerCase());
  }

  static String _replaceAllIgnoreCase(
    String text,
    String pattern,
    String replacement,
  ) {
    if (pattern.isEmpty) return text;
    final escaped = RegExp.escape(pattern);
    return text.replaceAll(RegExp(escaped, caseSensitive: false), replacement);
  }
}

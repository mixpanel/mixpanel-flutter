import 'dart:ui';

import '../../models/masking_directive.dart';
import '../../models/session_event.dart';
import '../../models/wireframe.dart';
import '../../models/wireframes_options.dart';
import '../logger.dart';

/// Post-processes raw wireframe elements (from the [MaskDetector] walk)
/// by applying geometric leak prevention and user rules, then text cleaning
/// (null bare icon glyphs / blank text) and truncation, dedup, invokes the
/// optional debug callback, and returns a [WireframePayload] ready to
/// enqueue.
///
/// Per the Wireframe Capture Contract, every collected semantic element is
/// emitted — a textless `button`/`input`/`image` is meaningful structure
/// (role + bounds), so elements are never dropped merely for lacking text.
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
    // Geometric masking → user rules → text cleaning → truncation, per
    // element. No drop stage: textless elements are kept as role + bounds
    // shells (see [_cleanText] and the Wireframe Capture Contract).
    final processed = rawElements
        .map((el) => _applyGeometricMasking(el, maskRegions))
        .map(_applyRules)
        .map(_cleanText)
        .map(_truncate)
        .toList(growable: false);

    // No elements were collected at all; skip rather than shipping an empty
    // payload. (Individual textless elements are NOT dropped.)
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
    // Anything already decided is left alone. That includes
    // [MaskDecision.declared]: developer-declared text is authored, not
    // scraped from the pixels, so it is exempt from the geometric strip —
    // including its own mask region. It survives even when the element is
    // masked (the pixels are still grayed by that region; the label still
    // describes the element for the AI summary). User rules below still run
    // over it as a safety net.
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
    if (el.maskDecision != MaskDecision.none &&
        el.maskDecision != MaskDecision.declared) {
      return el;
    }
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

  /// Normalizes an unmasked element's text for the wire without dropping the
  /// element:
  /// - blank / whitespace-only text → null
  /// - bare icon-font glyphs (private-use codepoints only) → null
  ///
  /// Text carrying any human-readable character is kept verbatim (e.g. a
  /// button labeled "Settings ⚙" keeps its label). The element itself is
  /// always retained — a textless `button`/`input`/`image` is meaningful
  /// structure (role + bounds), per the Wireframe Capture Contract.
  /// Elements already masked (`maskDecision != none`) have null text and
  /// pass through untouched.
  WireframeElement _cleanText(WireframeElement el) {
    // Declared text is authored by the developer, not scraped, so it is taken
    // verbatim — no blank/glyph normalization. (An empty declared string is
    // simply passed through; developers who want no text omit `wireframeText`.)
    if (el.maskDecision == MaskDecision.declared) return el;
    final text = el.text;
    if (text == null) return el;
    if (text.trim().isEmpty) return el.copyWith(clearText: true);
    if (!wireframeTextIsHumanReadable(text)) {
      return el.copyWith(clearText: true);
    }
    return el;
  }

  /// Truncate long text so the emitted value never exceeds
  /// [WireframeConstants.maxTextLength] characters — the
  /// [WireframeConstants.ellipsis] is paid for out of that budget, not added
  /// on top of it. Applied last so rule-rewrites are visible in the truncated
  /// output.
  WireframeElement _truncate(WireframeElement el) {
    final text = el.text;
    if (text == null || text.length <= WireframeConstants.maxTextLength) {
      return el;
    }
    final truncated =
        text.substring(0, WireframeConstants.maxTextLength - 1) +
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

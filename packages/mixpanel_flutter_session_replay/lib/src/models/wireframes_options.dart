import 'dart:convert';

/// Configuration for wireframe capture.
///
/// Wireframes are structured, per-frame lists of visible UI elements (role,
/// visible text, bounds) that ship as rrweb Custom events alongside the
/// existing screenshot stream. Downstream tooling can read the structured
/// timeline instead of pixels.
///
/// Wireframe capture is opt-in: pass a non-null [WireframesOptions] to
/// [SessionReplayOptions.wireframesOptions] to enable it. Existing session
/// replay integrations see no change until they ask for it.
///
/// Every masking guarantee the screenshot honors, the wireframe honors too —
/// enforced structurally by a three-layer masking pipeline (view-level,
/// geometric, and user rules).
///
/// Example:
/// ```dart
/// SessionReplayOptions(
///   wireframesOptions: WireframesOptions(
///     sensitiveRules: [
///       RedactRegexRule(RegExp(r'\d{3}-\d{2}-\d{4}'), replacement: '[SSN]'),
///       StripRule('password'),
///     ],
///   ),
/// )
/// ```
class WireframesOptions {
  const WireframesOptions({this.sensitiveRules = const [], this.debugEmitter});

  /// Content-level privacy rules applied to element text after view-level
  /// masking. Rules are applied in the declared order — see [SensitiveRule].
  final List<SensitiveRule> sensitiveRules;

  /// Optional per-emit debug callback for local inspection. Never sent to
  /// Mixpanel. The [WireframeSnapshot] JSON shape and [MaskDecision]
  /// enum names are meant for interactive debugging and are NOT a stable
  /// contract.
  ///
  /// The callback is invoked after a wireframe frame is successfully emitted.
  /// Exceptions thrown from the callback are caught and logged; they never
  /// crash the SDK.
  final void Function(WireframeSnapshot)? debugEmitter;
}

/// A content-level privacy rule applied to wireframe element text.
///
/// Rules are applied in the order they are declared. Later rules only see
/// text that survived earlier ones:
///
/// - `StripRule` / `StripRegexRule`: drop the element's text entirely; the element
///   stays with `text = null` so its bounds still ship. Short-circuits — no
///   later rule runs for that element.
/// - `RedactRule` / `RedactRegexRule`: replace matches in place; the element stays
///   with rewritten text. The next rule sees the rewritten value.
///
/// Text rules match case-insensitively. Regex rules honor whatever options
/// the caller compiled the [RegExp] with.
sealed class SensitiveRule {
  const SensitiveRule();
}

/// Replace occurrences of [text] (case-insensitive substring) with
/// [replacement]. Element stays; text is rewritten.
class RedactRule extends SensitiveRule {
  const RedactRule(this.text, {this.replacement = '[REDACTED]'});
  final String text;
  final String replacement;
}

/// Drop the element's text entirely when it contains [text]
/// (case-insensitive substring). Element stays with `text = null` so its
/// bounds still ship.
class StripRule extends SensitiveRule {
  const StripRule(this.text);
  final String text;
}

/// Replace all matches of [regex] with [replacement]. Element stays; text is
/// rewritten.
class RedactRegexRule extends SensitiveRule {
  const RedactRegexRule(this.regex, {this.replacement = '[REDACTED]'});
  final RegExp regex;
  final String replacement;
}

/// Drop the element's text entirely when [regex] matches. Element stays with
/// `text = null` so its bounds still ship.
class StripRegexRule extends SensitiveRule {
  const StripRegexRule(this.regex);
  final RegExp regex;
}

/// Which masking layer nulled or rewrote an element's text.
///
/// Delivered as part of [WireframeSnapshotElement] inside [WireframeSnapshot]. Not
/// sent to Mixpanel; useful only for local debugging.
enum MaskDecision {
  /// Text emitted as-is.
  none,

  /// Explicitly masked via `MixpanelMask` widget context.
  explicit,

  /// Auto-masked based on `AutoMaskedView` type match (text/image).
  auto,

  /// Text-entry field — always masked, cannot be overridden.
  textEntry,

  /// Bounds intersected a mask rect the screenshot is drawing — leak
  /// prevention.
  geometric,

  /// Matched a `StripRule` / `StripRegexRule` rule.
  ruleStrip,

  /// Matched a `RedactRule` / `RedactRegexRule` rule (text present but rewritten).
  ruleRedact,
}

String _maskDecisionWireName(MaskDecision decision) {
  switch (decision) {
    case MaskDecision.none:
      return 'NONE';
    case MaskDecision.explicit:
      return 'EXPLICIT';
    case MaskDecision.auto:
      return 'AUTO';
    case MaskDecision.textEntry:
      return 'TEXT_ENTRY';
    case MaskDecision.geometric:
      return 'GEOMETRIC';
    case MaskDecision.ruleStrip:
      return 'RULE_STRIP';
    case MaskDecision.ruleRedact:
      return 'RULE_REDACT';
  }
}

/// A snapshot delivered to [WireframesOptions.debugEmitter] after each
/// wireframe frame is emitted.
///
/// **Not a stable contract.** The JSON shape and enum names are for
/// interactive debugging only and may change without notice.
class WireframeSnapshot {
  const WireframeSnapshot({
    required this.timestamp,
    required this.viewport,
    required this.elements,
  });

  /// Milliseconds since epoch (matches the accompanying screenshot's
  /// timestamp for time alignment).
  final int timestamp;

  /// `[width, height]` in logical pixels.
  final List<int> viewport;

  /// Elements captured this frame, in traversal order.
  final List<WireframeSnapshotElement> elements;

  /// Serialize to a JSON string. Debug JSON — NOT a stable contract.
  String toJson() {
    return jsonEncode({
      'timestamp': timestamp,
      'viewport': viewport,
      'elements': elements
          .map(
            (e) => {
              'role': e.role,
              'text': e.text,
              'bounds': e.bounds,
              'maskDecision': _maskDecisionWireName(e.maskDecision),
            },
          )
          .toList(),
    });
  }
}

/// A single element in [WireframeSnapshot.elements].
class WireframeSnapshotElement {
  const WireframeSnapshotElement({
    required this.role,
    required this.text,
    required this.bounds,
    required this.maskDecision,
  });

  /// One of `"text"`, `"button"`, `"input"`, `"image"`.
  final String role;

  /// Visible label or content description; `null` when masked or absent.
  final String? text;

  /// `[x, y, w, h]` in window-relative logical pixels.
  final List<int> bounds;

  /// Which masking layer nulled or rewrote the text (or [MaskDecision.none]
  /// if the text passed through unchanged).
  final MaskDecision maskDecision;
}

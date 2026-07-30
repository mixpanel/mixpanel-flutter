import 'dart:ui';

import 'wireframes_options.dart' show MaskDecision;

/// Role of a wireframe element as sent on the wire.
enum WireframeRole {
  text,
  button,
  input,
  image;

  /// Wire-format lowercase name.
  String get wireName => name;
}

/// A single UI element captured for a wireframe frame.
///
/// Internal representation used between the mask-detector walk (which fills
/// [role], [text], [bounds], and the initial [maskDecision]) and the
/// [WireframeEmitter] (which applies geometric leak prevention and user
/// sensitive rules, then serializes).
class WireframeElement {
  const WireframeElement({
    required this.role,
    required this.text,
    required this.bounds,
    required this.maskDecision,
    this.declared = false,
  });

  /// Element role.
  final WireframeRole role;

  /// Visible text; `null` when masked by any layer or when the element has
  /// no natural text (e.g. an input field, or an image with no semantics
  /// label).
  final String? text;

  /// Element bounds in boundary-relative logical pixels — same coordinate
  /// space as `MaskRegionInfo.bounds`, so the geometric-masking intersection
  /// works directly.
  final Rect bounds;

  /// Which layer produced this element's text state.
  final MaskDecision maskDecision;

  /// Whether [text] was authored by the developer (via
  /// `MixpanelMask(wireframeText:)` / `MixpanelUnmask(wireframeText:)`) rather
  /// than scraped from the widget.
  ///
  /// Declared text is orthogonal to masking: it is **exempt from the geometric
  /// strip** (including its own mask region), so it survives even when the
  /// pixels are masked — masking hides the pixels while the declared text still
  /// describes the element for the AI summary. User `SensitiveRule`s still run
  /// over it as a safety net.
  final bool declared;

  /// Return a copy with the given fields replaced.
  WireframeElement copyWith({
    WireframeRole? role,
    String? text,
    bool clearText = false,
    Rect? bounds,
    MaskDecision? maskDecision,
    bool? declared,
  }) {
    return WireframeElement(
      role: role ?? this.role,
      text: clearText ? null : (text ?? this.text),
      bounds: bounds ?? this.bounds,
      maskDecision: maskDecision ?? this.maskDecision,
      declared: declared ?? this.declared,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WireframeElement &&
          role == other.role &&
          text == other.text &&
          bounds == other.bounds &&
          maskDecision == other.maskDecision &&
          declared == other.declared;

  @override
  int get hashCode => Object.hash(role, text, bounds, maskDecision, declared);
}

/// Shared wireframe constants.
class WireframeConstants {
  /// Maximum text length in wireframe elements. Longer text is truncated
  /// with [ellipsis].
  static const int maxTextLength = 60;

  /// Ellipsis appended to truncated text.
  static const String ellipsis = '…';
}

/// True if [text] contains at least one character outside the Unicode
/// private-use area (U+E000–U+F8FF), where icon fonts place their glyphs.
///
/// A string that fails this check is a bare icon glyph (e.g. a Material
/// Icons codepoint), not human-readable content. Two callers rely on this:
/// the mask detector, which refuses to treat an icon glyph as a button
/// label, and the emitter, which nulls such text on the wire so the AI
/// never receives a garbage glyph. The element's role + bounds shell is
/// kept regardless — see the Wireframe Capture Contract.
bool wireframeTextIsHumanReadable(String text) {
  for (final rune in text.runes) {
    if (rune < 0xE000 || rune > 0xF8FF) return true;
  }
  return false;
}

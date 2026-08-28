import 'package:flutter/widgets.dart';

/// A widget that explicitly marks its child as safe (unmasked)
///
/// Use this to prevent auto-masking on specific widgets.
/// This is useful when you have images or non-sensitive text that should not be masked.
/// MixpanelUnmask is ignored for all RenderEditable types (e.g., TextField) to avoid leaking sensitive user input.
///
/// Example:
/// ```dart
/// MixpanelUnmask(
///   Text('Public information'), // Will be unmasked
/// )
/// ```
///
/// ## Declaring wireframe text
///
/// Pass [wireframeText] to attach an authored label to this element in the
/// `mp_wireframe` event — useful for custom-drawn content the walker can't read
/// (a `CustomPaint` chart) or to override the scraped text with an analytical
/// label. The text (and the emitted element's role + bounds) is applied to this
/// widget's **direct child**.
///
/// Declared text is authored by you, not scraped from the screen, so ensure it
/// is not itself sensitive. It still runs through the configured `SensitiveRule`s
/// as a safety net.
///
/// ```dart
/// MixpanelUnmask(
///   wireframeText: 'monthly spend',
///   child: CustomPaint(painter: SpendChartPainter()),
/// )
/// ```
class MixpanelUnmask extends StatelessWidget {
  const MixpanelUnmask({super.key, required this.child, this.wireframeText});

  /// The widget to exclude from masking in session replay recordings
  final Widget child;

  /// Authored text recorded for this element in the `mp_wireframe` event.
  ///
  /// **Beta.** Wireframes are in beta; see `WireframesOptions` for what to check
  /// before shipping to production.
  ///
  /// Applied to the [child] (its role + bounds). `null` (default) declares no
  /// text. See the class docs for the privacy contract.
  ///
  /// A `TextField` child emits the declared label as its `input` element — the
  /// label describes the field, and the typed value is still never sent,
  /// because declared text replaces scraped text rather than adding to it.
  final String? wireframeText;

  @override
  Widget build(BuildContext context) {
    // The MaskDetector finds this widget during element tree traversal
    // and prevents auto-masking for this widget and all its children
    return child;
  }
}

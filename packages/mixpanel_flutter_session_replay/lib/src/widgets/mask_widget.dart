import 'package:flutter/widgets.dart';

/// A widget that masks its child for session replay privacy
///
/// Wrap any widget with this to ensure it's masked in recordings.
/// This widget is detected during mask detection by traversing the element tree.
///
/// Example:
/// ```dart
/// MixpanelMask(
///   child: TextField(
///     decoration: InputDecoration(labelText: 'Credit Card'),
///   ),
/// )
/// ```
///
/// ## Declaring wireframe text
///
/// Masking and declared wireframe text are orthogonal. Pass [wireframeText] to
/// attach an authored label to this element in the `mp_wireframe` event — useful
/// for custom-drawn content the walker can't read (a `CustomPaint` chart) or to
/// describe a masked view for the AI summary.
///
/// **The declared text is sent even though the pixels are masked.** Masking
/// draws an opaque rectangle over the pixels (they are never captured); the
/// declared text is authored by you, not scraped from the screen, so masking
/// has no bearing on it. Because it is authored, it is your responsibility to
/// ensure [wireframeText] is not itself sensitive — if it could be, omit it.
///
/// The text (and the emitted element's role + bounds) is applied to this
/// widget's **direct child**.
///
/// ```dart
/// MixpanelMask(
///   wireframeText: 'profile photo',
///   child: Image.asset('avatar.png'),
/// )
/// ```
///
/// This works on a text field too. The label describes the field; the value the
/// user types is still never emitted, because declared text replaces scraped
/// text rather than adding to it.
///
/// ```dart
/// MixpanelMask(
///   wireframeText: 'Card number',
///   child: TextField(controller: cardNumberController),
/// )
/// ```
class MixpanelMask extends StatelessWidget {
  const MixpanelMask({super.key, required this.child, this.wireframeText});

  /// The widget to mask in session replay recordings
  final Widget child;

  /// Authored text recorded for this element in the `mp_wireframe` event.
  ///
  /// Orthogonal to masking — sent even though the child's pixels are masked.
  /// Applied to the [child] (its role + bounds). `null` (default) declares no
  /// text. See the class docs for the privacy contract.
  final String? wireframeText;

  @override
  Widget build(BuildContext context) {
    // The MaskDetector finds this widget during element tree traversal
    // and masks it along with all its children
    return child;
  }
}

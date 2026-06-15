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
class MixpanelUnmask extends StatelessWidget {
  const MixpanelUnmask({super.key, required this.child});

  /// The widget to exclude from masking in session replay recordings
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The MaskDetector finds this widget during element tree traversal
    // and prevents auto-masking for this widget and all its children
    return child;
  }
}

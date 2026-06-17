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
class MixpanelMask extends StatelessWidget {
  const MixpanelMask({super.key, required this.child});

  /// The widget to mask in session replay recordings
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The MaskDetector finds this widget during element tree traversal
    // and masks it along with all its children
    return child;
  }
}

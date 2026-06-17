import 'package:flutter/material.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';

/// Masking state for components
enum MaskState {
  masked, // Wrap in MixpanelMask
  unmasked, // Wrap in MixpanelUnmask
  defaultState, // No wrapper (use default behavior)
}

/// Screen testing image/container masking with colored boxes
class ImageGalleryScreen extends StatelessWidget {
  const ImageGalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Gallery Test'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1,
        ),
        itemCount: _imageData.length,
        itemBuilder: (context, index) {
          final image = _imageData[index];

          // Helper function to apply mask state
          Widget applyMaskState(Widget widget, MaskState state) {
            switch (state) {
              case MaskState.masked:
                return MixpanelMask(child: widget);
              case MaskState.unmasked:
                return MixpanelUnmask(child: widget);
              case MaskState.defaultState:
                return widget;
            }
          }

          // Build icon with mask state
          final iconWidget = Icon(image.icon, size: 48, color: Colors.white);
          final styledIcon = applyMaskState(iconWidget, image.iconState);

          // Build label with mask state
          final labelWidget = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              image.label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          );
          final styledLabel = applyMaskState(labelWidget, image.labelState);

          // Build container with mask state
          final container = Container(
            decoration: BoxDecoration(
              color: image.color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [styledIcon, const SizedBox(height: 8), styledLabel],
            ),
          );

          return applyMaskState(container, image.backgroundState);
        },
      ),
    );
  }
}

class _ImageData {
  const _ImageData({
    required this.label,
    required this.color,
    required this.icon,
    this.backgroundState = MaskState.defaultState,
    this.iconState = MaskState.defaultState,
    this.labelState = MaskState.defaultState,
  });

  final String label;
  final Color color;
  final IconData icon;
  final MaskState backgroundState;
  final MaskState iconState;
  final MaskState labelState;
}

const List<_ImageData> _imageData = [
  _ImageData(label: 'Default Behavior', color: Colors.blue, icon: Icons.info),
  _ImageData(
    label: 'All Masked',
    color: Colors.blueGrey,
    icon: Icons.lock,
    backgroundState: MaskState.masked,
    iconState: MaskState.masked,
    labelState: MaskState.masked,
  ),
  _ImageData(
    label: 'All Unmasked',
    color: Colors.green,
    icon: Icons.lock_open,
    backgroundState: MaskState.unmasked,
    iconState: MaskState.unmasked,
    labelState: MaskState.unmasked,
  ),
  _ImageData(
    label: 'Background Container Masked, children inherit mask',
    color: Colors.teal,
    icon: Icons.image,
    backgroundState: MaskState.masked,
  ),
  _ImageData(
    label: 'Background Container Unmasked, children inherit unmask',
    color: Colors.purple,
    icon: Icons.wallpaper,
    backgroundState: MaskState.unmasked,
  ),
  _ImageData(
    label: 'Icon Masked Only, Others Default',
    color: Colors.pink,
    icon: Icons.star,
    iconState: MaskState.masked,
  ),
  _ImageData(
    label: 'Icon Unmasked Only, Others Default',
    color: Colors.teal,
    icon: Icons.star_border,
    iconState: MaskState.unmasked,
  ),
  _ImageData(
    label: 'Label Masked Only, Others Default',
    color: Colors.brown,
    icon: Icons.text_fields,
    labelState: MaskState.masked,
  ),
  _ImageData(
    label: 'Label Unmasked Only, Others Default',
    color: Colors.indigo,
    icon: Icons.title,
    labelState: MaskState.unmasked,
  ),
  _ImageData(
    label: 'Background Container Unmasked, redundant child unmask',
    color: Colors.lightBlue,
    icon: Icons.shuffle,
    backgroundState: MaskState.unmasked,
    iconState: MaskState.unmasked,
  ),
  _ImageData(
    label: 'BG Unmasked + Label Masked, Icon default',
    color: Colors.cyan,
    icon: Icons.swap_horiz,
    backgroundState: MaskState.unmasked,
    labelState: MaskState.masked,
  ),
];

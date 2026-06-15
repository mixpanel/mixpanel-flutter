import 'package:flutter/material.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';

import '../utils/constants.dart';
import '../widgets/test_screen_card.dart';

/// Dashboard tab with test screen launchers
class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Test Scenarios',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        TestScreenCard(
          title: 'Event Triggers',
          description:
              'Fire test events with bool / int / string / mixed properties',
          icon: Icons.bolt,
          onTap: () => Navigator.pushNamed(context, AppRoutes.eventTriggers),
        ),
        TestScreenCard(
          title: 'Mixed Content',
          description:
              'JSON-driven test with text, images, and nested containers',
          icon: Icons.view_module,
          onTap: () => Navigator.pushNamed(context, AppRoutes.mixedContent),
        ),
        TestScreenCard(
          title: 'Animations',
          description: 'Various animation types (fade, scale, rotate, slide)',
          icon: Icons.animation,
          onTap: () => Navigator.pushNamed(context, AppRoutes.animations),
        ),
        TestScreenCard(
          title: 'Visibility Variations',
          description: 'Test different visibility states and opacity',
          icon: Icons.visibility,
          onTap: () => Navigator.pushNamed(context, AppRoutes.visibility),
        ),
        TestScreenCard(
          title: 'Text Input Forms',
          description: 'Various TextField types with masking',
          icon: Icons.edit,
          onTap: () => Navigator.pushNamed(context, AppRoutes.textInput),
        ),
        TestScreenCard(
          title: 'Image Gallery',
          description: 'Colored container images to test masking',
          icon: Icons.image,
          onTap: () => Navigator.pushNamed(context, AppRoutes.imageGallery),
        ),
        TestScreenCard(
          title: 'Security Enforcement',
          description: 'TextField always masked (even in MixpanelUnmask)',
          icon: Icons.security,
          onTap: () => Navigator.pushNamed(context, AppRoutes.security),
        ),
        TestScreenCard(
          title: 'Rapid Scroll / Performance',
          description: '1000+ items list for performance testing',
          icon: Icons.speed,
          onTap: () => Navigator.pushNamed(context, AppRoutes.rapidScroll),
        ),
        TestScreenCard(
          title: 'Platform Widgets',
          description: 'Material vs Cupertino widgets side-by-side',
          icon: Icons.phonelink,
          onTap: () => Navigator.pushNamed(context, AppRoutes.platformWidgets),
        ),
        TestScreenCard(
          title: 'Dialog Test',
          description: 'Open a dialog with mixed content',
          icon: Icons.dialpad,
          onTap: () => _showTestDialog(context),
        ),
      ],
    );
  }

  void _showTestDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Test Dialog'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This is a dialog with mixed content'),
              const SizedBox(height: 16),
              MixpanelMask(
                child: const Text(
                  'Masked text: Sensitive info 123-45-6789',
                  style: TextStyle(color: Colors.red),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: 150,
                height: 100,
                color: Colors.blue,
                child: const Center(
                  child: Text(
                    'Unmasked Image',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              MixpanelMask(
                child: Container(
                  width: 150,
                  height: 100,
                  color: Colors.green,
                  child: const Center(
                    child: Text(
                      'Masked Image',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const TextField(
                decoration: InputDecoration(
                  labelText: 'Enter text here',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

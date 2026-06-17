import 'package:flutter/material.dart';

/// Screen testing different visibility states
class VisibilityScreen extends StatefulWidget {
  const VisibilityScreen({super.key});

  @override
  State<VisibilityScreen> createState() => _VisibilityScreenState();
}

class _VisibilityScreenState extends State<VisibilityScreen> {
  bool _isVisible = true;
  bool _isOffstage = false;
  double _opacity = 1.0;
  bool _conditionalRender = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visibility Variations Test'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildTestCard(
            'Visibility Widget',
            Visibility(
              visible: _isVisible,
              child: _buildTestBox('Visibility Widget', Colors.blue),
            ),
            SwitchListTile(
              title: const Text('Visible'),
              value: _isVisible,
              onChanged: (value) => setState(() => _isVisible = value),
            ),
          ),
          _buildTestCard(
            'Offstage Widget',
            Stack(
              children: [
                Offstage(
                  offstage: _isOffstage,
                  child: _buildTestBox('Offstage Widget', Colors.green),
                ),
                if (_isOffstage)
                  Container(
                    height: 100,
                    color: Colors.grey[300],
                    child: const Center(child: Text('Widget is offstage')),
                  ),
              ],
            ),
            SwitchListTile(
              title: const Text('Offstage'),
              value: _isOffstage,
              onChanged: (value) => setState(() => _isOffstage = value),
            ),
          ),
          _buildTestCard(
            'Opacity Widget',
            Opacity(
              opacity: _opacity,
              child: _buildTestBox('Opacity Widget', Colors.cyan),
            ),
            Column(
              children: [
                Slider(
                  value: _opacity,
                  onChanged: (value) => setState(() => _opacity = value),
                  min: 0.0,
                  max: 1.0,
                  divisions: 10,
                  label: _opacity.toStringAsFixed(1),
                ),
                Text('Opacity: ${_opacity.toStringAsFixed(1)}'),
              ],
            ),
          ),
          _buildTestCard(
            'Conditional Rendering',
            _conditionalRender
                ? _buildTestBox('Conditionally Rendered', Colors.purple)
                : Container(
                    height: 100,
                    color: Colors.grey[300],
                    child: const Center(child: Text('Widget not rendered')),
                  ),
            SwitchListTile(
              title: const Text('Render Widget'),
              value: _conditionalRender,
              onChanged: (value) => setState(() => _conditionalRender = value),
            ),
          ),
          _buildTestCard(
            'Overlapping Widgets (Z-index)',
            SizedBox(
              height: 200,
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    child: _buildTestBox('Back (Z=1)', Colors.lime, size: 120),
                  ),
                  Positioned(
                    top: 40,
                    left: 40,
                    child: _buildTestBox(
                      'Middle (Z=2)',
                      Colors.teal,
                      size: 120,
                    ),
                  ),
                  Positioned(
                    top: 80,
                    left: 80,
                    child: _buildTestBox('Front (Z=3)', Colors.pink, size: 120),
                  ),
                ],
              ),
            ),
            const Text('Three overlapping containers'),
          ),
        ],
      ),
    );
  }

  Widget _buildTestCard(String title, Widget content, Widget controls) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            content,
            const SizedBox(height: 16),
            controls,
          ],
        ),
      ),
    );
  }

  Widget _buildTestBox(String label, Color color, {double size = 100}) {
    return Container(
      width: size,
      height: size,
      color: color,
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

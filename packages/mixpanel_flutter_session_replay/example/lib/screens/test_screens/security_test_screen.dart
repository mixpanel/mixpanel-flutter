import 'package:flutter/material.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';

/// Screen testing security enforcement for input fields
///
/// Demonstrates that TextField/TextFormField are ALWAYS masked,
/// even inside MixpanelUnmask containers (matching Android behavior)
class SecurityTestScreen extends StatelessWidget {
  const SecurityTestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Security Enforcement Tests'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Test Case 1: TextField in safe container (ALWAYS masked)
          _buildTestCard(
            title: '🔒 SECURITY: TextField in Safe Container',
            subtitle: 'TextField is ALWAYS masked, even in MixpanelUnmask',
            color: Colors.indigo.shade50,
            borderColor: Colors.indigo.shade700,
            child: MixpanelUnmask(
              child: Column(
                children: [
                  const Text(
                    'This text is unmasked (safe container)',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: TextEditingController(text: 'password123'),
                    decoration: const InputDecoration(
                      labelText: 'Password (ALWAYS MASKED)',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '⚠️ TextField is masked despite parent MixpanelUnmask',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Test Case 2: Multiple input fields in safe container
          _buildTestCard(
            title: '🔒 SECURITY: Multiple Input Fields',
            subtitle: 'All input fields masked in safe container',
            color: Colors.cyan.shade50,
            borderColor: Colors.cyan.shade700,
            child: MixpanelUnmask(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Login Form (in MixpanelUnmask)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: TextEditingController(text: 'user@example.com'),
                    decoration: const InputDecoration(
                      labelText: 'Email (MASKED)',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: TextEditingController(text: 'secret123'),
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password (MASKED)',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '✓ Both fields are masked for security',
                    style: TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Test Case 3: Nested safe containers with input
          _buildTestCard(
            title: '🔒 SECURITY: Nested Safe Containers',
            subtitle: 'TextField masked even in deeply nested MixpanelUnmask',
            color: Colors.purple.shade50,
            borderColor: Colors.purple.shade700,
            child: MixpanelUnmask(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: MixpanelUnmask(
                  child: Column(
                    children: [
                      const Text('Nested safe container level 1'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            const Text('Nested safe container level 2'),
                            const SizedBox(height: 8),
                            TextField(
                              controller: TextEditingController(
                                text: 'Still masked!',
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Deep nested TextField (MASKED)',
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Test Case 4: TextFormField also enforced
          _buildTestCard(
            title: '🔒 SECURITY: TextFormField',
            subtitle: 'TextFormField is also always masked',
            color: Colors.teal.shade50,
            borderColor: Colors.teal.shade700,
            child: MixpanelUnmask(
              child: Column(
                children: [
                  const Text('Form in safe container'),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: 'credit-card-4111',
                    decoration: const InputDecoration(
                      labelText: 'Credit Card (MASKED)',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '✓ TextFormField security enforced',
                    style: TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Comparison: Regular Text in safe container (unmasked)
          _buildTestCard(
            title: '✅ COMPARISON: Regular Text Unmasked',
            subtitle: 'Non-input content IS unmasked in safe container',
            color: Colors.green.shade50,
            borderColor: Colors.green.shade700,
            child: MixpanelUnmask(
              child: Column(
                children: [
                  const Text(
                    'This is regular Text widget',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'It is NOT masked because:',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '1. It\'s inside MixpanelUnmask\n'
                    '2. It\'s NOT an input field\n'
                    '3. Security override only applies to editable text',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '✓ Regular text correctly unmasked',
                    style: TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Security rationale
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              border: Border.all(color: Colors.blue.shade700, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.security, color: Colors.blue),
                    SizedBox(width: 8),
                    Text(
                      'Security Rationale',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Text(
                  'Input fields (TextField, TextFormField, etc.) are ALWAYS '
                  'masked in session replays to prevent credential leakage, '
                  'even if accidentally wrapped in MixpanelUnmask.',
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 8),
                Text(
                  'This security enforcement matches the Android SDK behavior '
                  'where EditText and Compose EditableText cannot be unmasked.',
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 8),
                Text(
                  'Developer Note: MixpanelUnmask only affects non-input '
                  'content like Text widgets and Images.',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestCard({
    required String title,
    required String subtitle,
    required Color color,
    required Color borderColor,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: borderColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

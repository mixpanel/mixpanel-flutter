import 'package:flutter/material.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';

/// Screen testing various text input types
class TextInputScreen extends StatefulWidget {
  const TextInputScreen({super.key});

  @override
  State<TextInputScreen> createState() => _TextInputScreenState();
}

class _TextInputScreenState extends State<TextInputScreen> {
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Text Input Forms Test'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Regular (Unmasked) Inputs',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Product Code',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.qr_code),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Sensitive (Masked) Inputs',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            MixpanelMask(
              child: TextFormField(
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
            ),
            const SizedBox(height: 16),
            MixpanelMask(
              child: TextFormField(
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
              ),
            ),
            const SizedBox(height: 16),
            MixpanelMask(
              child: TextFormField(
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                  hintText: '(555) 123-4567',
                ),
              ),
            ),
            const SizedBox(height: 16),
            MixpanelMask(
              child: TextFormField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Credit Card',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.credit_card),
                  hintText: '1234 5678 9012 3456',
                ),
              ),
            ),
            const SizedBox(height: 16),
            MixpanelMask(
              child: TextFormField(
                decoration: const InputDecoration(
                  labelText: 'SSN',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.shield),
                  hintText: '123-45-6789',
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Multi-line Input',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextFormField(
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Comments (Unmasked)',
                border: OutlineInputBorder(),
                hintText: 'Enter your comments here...',
              ),
            ),
            const SizedBox(height: 16),
            MixpanelMask(
              child: TextFormField(
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Private Notes (Masked)',
                  border: OutlineInputBorder(),
                  hintText: 'Enter sensitive notes here...',
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Form submitted!')),
                  );
                }
              },
              child: const Text('Submit Form'),
            ),
          ],
        ),
      ),
    );
  }
}

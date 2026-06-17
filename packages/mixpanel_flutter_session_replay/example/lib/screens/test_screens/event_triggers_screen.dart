import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../main.dart';
import '../../services/mixpanel_analytics.dart';

/// Demo screen for Event Triggers.
///
/// Each card fires a Mixpanel event with one of several property variants
/// designed to test both match and no-match cases of a server-configured
/// trigger. Use the suggested filter on each card as a starting point in
/// the Mixpanel dashboard, then verify each button below it produces the
/// expected match / no-match result.
class EventTriggersScreen extends StatelessWidget {
  const EventTriggersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sdk = context.watch<MixpanelModel>().sdk;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Event Triggers'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined),
            tooltip: 'Stop recording',
            onPressed: () {
              sdk?.stopRecording();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('stopRecording() called'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _TriggerCard(
            title: 'Boolean match',
            eventName: 'test_bool_trigger',
            filterHint: '{"===":[{"var":"enabled"},true]}',
            variants: [
              {'enabled': true},
              {'enabled': false},
            ],
          ),
          _TriggerCard(
            title: 'Int match (try >= 100)',
            eventName: 'test_int_trigger',
            filterHint: '{">=":[{"var":"score"},100]}',
            variants: [
              {'score': 50},
              {'score': 100},
              {'score': 200},
            ],
          ),
          _TriggerCard(
            title: 'String match',
            eventName: 'test_string_trigger',
            filterHint: '{"===":[{"var":"tier"},"premium"]}',
            variants: [
              {'tier': 'free'},
              {'tier': 'premium'},
              {'tier': 'PREMIUM'},
            ],
          ),
          _TriggerCard(
            title: 'Mixed (bool + int + string)',
            eventName: 'test_mixed_trigger',
            filterHint:
                '{"and":['
                '{"===":[{"var":"enabled"},true]},'
                '{">=":[{"var":"score"},100]},'
                '{"===":[{"var":"tier"},"premium"]}'
                ']}',
            variants: [
              {'enabled': true, 'score': 200, 'tier': 'premium'},
              {'enabled': false, 'score': 200, 'tier': 'premium'},
              {'enabled': true, 'score': 50, 'tier': 'premium'},
              {'enabled': true, 'score': 200, 'tier': 'free'},
            ],
          ),
        ],
      ),
    );
  }
}

class _TriggerCard extends StatelessWidget {
  const _TriggerCard({
    required this.title,
    required this.eventName,
    required this.filterHint,
    required this.variants,
  });

  final String title;
  final String eventName;
  final String filterHint;
  final List<Map<String, Object>> variants;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _LabeledRow(label: 'Event', value: eventName),
            const SizedBox(height: 4),
            _LabeledRow(label: 'Suggested filter', value: filterHint),
            const SizedBox(height: 12),
            for (final variant in variants) ...[
              _VariantButton(eventName: eventName, properties: variant),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _VariantButton extends StatelessWidget {
  const _VariantButton({required this.eventName, required this.properties});

  final String eventName;
  final Map<String, Object> properties;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.play_arrow, size: 18),
        label: Text(_formatProperties(properties)),
        onPressed: () {
          MixpanelAnalytics.instance?.track(eventName, properties: properties);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Tracked: $eventName  $properties'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }

  static String _formatProperties(Map<String, Object> properties) {
    return properties.entries.map((e) => '${e.key}: ${e.value}').join(',  ');
  }
}

class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}

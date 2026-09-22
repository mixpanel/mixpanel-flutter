import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/config_model.dart';

/// Demonstrates configuring replay behavior when the app or page leaves the
/// foreground.
class BackgroundBehaviorScreen extends StatefulWidget {
  const BackgroundBehaviorScreen({super.key});

  @override
  State<BackgroundBehaviorScreen> createState() =>
      _BackgroundBehaviorScreenState();
}

class _BackgroundBehaviorScreenState extends State<BackgroundBehaviorScreen> {
  late final TextEditingController _pauseIdleController;

  @override
  void initState() {
    super.initState();
    final config = context.read<ConfigModel>();
    _pauseIdleController = TextEditingController(
      text: config.backgroundPauseIdleSeconds,
    );
    _pauseIdleController.addListener(
      () => config.setBackgroundPauseIdleSeconds(_pauseIdleController.text),
    );
  }

  @override
  void dispose() {
    _pauseIdleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Background Recording Behavior')),
      body: Consumer<ConfigModel>(
        builder: (context, config, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                kIsWeb
                    ? 'Web defaults to pause so temporary tab switches keep '
                          'the same replay.'
                    : 'Mobile defaults to stop for backward compatibility.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<BackgroundBehaviorSelection>(
                value: config.backgroundBehavior,
                decoration: const InputDecoration(
                  labelText: 'When Leaving the Foreground',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: BackgroundBehaviorSelection.pause,
                    child: Text('Pause and retain replay'),
                  ),
                  DropdownMenuItem(
                    value: BackgroundBehaviorSelection.stop,
                    child: Text('Stop replay'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) config.setBackgroundBehavior(value);
                },
              ),
              if (config.backgroundBehavior ==
                  BackgroundBehaviorSelection.pause) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _pauseIdleController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Pause Idle Duration (seconds)',
                    border: const OutlineInputBorder(),
                    errorText: config.backgroundPauseIdleError,
                    helperText:
                        'Return before this duration to continue the same replay.',
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'Initialization example',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  _configurationExample(config),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _configurationExample(ConfigModel config) {
    final behavior = switch (config.backgroundBehavior) {
      BackgroundBehaviorSelection.pause =>
        'ReplayBackgroundBehavior.pause(\n'
            '  idleTimeout: Duration(seconds: '
            '${config.backgroundPauseIdleSeconds}),\n'
            ')',
      BackgroundBehaviorSelection.stop => 'ReplayBackgroundBehavior.stop',
    };
    final optionsType = kIsWeb ? 'WebOptions' : 'MobileOptions';
    final optionsName = kIsWeb ? 'web' : 'mobile';

    return 'PlatformOptions(\n'
        '  $optionsName: $optionsType(\n'
        '    onBackground: $behavior,\n'
        '  ),\n'
        ')';
  }
}

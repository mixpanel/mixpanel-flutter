import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../utils/constants.dart';

/// Settings tab with SDK controls
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final TextEditingController _distinctIdController = TextEditingController();
  RecordingState? _lastKnownState;
  Timer? _statePoller;

  @override
  void initState() {
    super.initState();
    _startStatePolling();
  }

  @override
  void dispose() {
    _statePoller?.cancel();
    _distinctIdController.dispose();
    super.dispose();
  }

  /// Polls recording state to catch async transitions (e.g. initializing → recording).
  /// The SDK's startRecording() transitions state asynchronously, so we poll until stable.
  void _startStatePolling() {
    _statePoller?.cancel();
    _statePoller = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final sdk = context.read<MixpanelModel>().sdk;
      final currentState = sdk?.recordingState;
      if (currentState != _lastKnownState) {
        _lastKnownState = currentState;
        if (mounted) setState(() {});
      }
    });
  }

  void _startRecording() {
    final sdk = context.read<MixpanelModel>().sdk;
    if (sdk != null) {
      sdk.startRecording(sessionsPercent: 100.0);
      setState(() {});
    }
  }

  void _stopRecording() {
    final sdk = context.read<MixpanelModel>().sdk;
    if (sdk != null) {
      sdk.stopRecording();
      setState(() {});
    }
  }

  void _identify(String distinctId) {
    context.read<MixpanelModel>().sdk?.identify(distinctId);
  }

  @override
  Widget build(BuildContext context) {
    // Get current SDK from Provider
    final sdk = context.watch<MixpanelModel>().sdk;
    final recordingState = sdk?.recordingState ?? RecordingState.notRecording;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'SDK Status',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _buildInfoCard('Current Status', [
          _buildInfoRow(
            'SDK Initialized',
            sdk != null ? 'YES' : 'NO',
            valueColor: sdk != null ? Colors.green : Colors.grey,
          ),
          _buildInfoRow(
            'Recording State',
            recordingState.name.toUpperCase(),
            valueColor: _getStateColor(recordingState),
          ),
        ]),
        const SizedBox(height: 24),
        const Text(
          'Recording Controls',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: recordingState == RecordingState.recording
                    ? null
                    : _startRecording,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Recording'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: recordingState == RecordingState.recording
                    ? _stopRecording
                    : null,
                icon: const Icon(Icons.stop),
                label: const Text('Stop Recording'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'Identity Management',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _distinctIdController,
          decoration: const InputDecoration(
            labelText: 'New Distinct ID',
            border: OutlineInputBorder(),
            hintText: 'Enter new distinct ID',
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () {
            final newId = _distinctIdController.text.trim();
            if (newId.isNotEmpty) {
              _identify(newId);
              _distinctIdController.clear();
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Identified as: $newId')));
            }
          },
          icon: const Icon(Icons.person),
          label: const Text('Update Distinct ID'),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),
        const Text(
          'Animation Speed',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('1x'),
            Expanded(
              child: Slider(
                value: timeDilation,
                min: 1.0,
                max: 20.0,
                divisions: 19,
                label: '${timeDilation.round()}x',
                onChanged: (value) {
                  setState(() {
                    timeDilation = value;
                  });
                },
              ),
            ),
            const Text('20x'),
          ],
        ),
        Text(
          'Current: ${timeDilation.round()}x slower',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),
        const Text(
          'Advanced',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Re-initialize SDK?'),
                  content: const Text(
                    'This will stop the current session and return to the configuration screen.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        // Navigate back to config screen
                        Navigator.pushReplacementNamed(
                          context,
                          AppRoutes.config,
                        );
                      },
                      child: const Text('Re-initialize'),
                    ),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Re-initialize SDK'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(String title, List<Widget> children) {
    return Card(
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
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Flexible(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w500, color: valueColor),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStateColor(RecordingState state) {
    switch (state) {
      case RecordingState.recording:
        return Colors.green;
      case RecordingState.initializing:
        return Colors.orange;
      case RecordingState.notRecording:
        return Colors.grey;
    }
  }
}

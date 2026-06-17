import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';
import 'package:provider/provider.dart';

import '../models/config_model.dart';
import '../services/mixpanel_analytics.dart';
import '../utils/constants.dart';

/// Configuration screen for SDK initialization
class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key, required this.onSdkInitialized});

  final void Function(MixpanelSessionReplay?) onSdkInitialized;

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  late TextEditingController _tokenController;
  late TextEditingController _distinctIdController;
  late TextEditingController _flushIntervalController;
  late TextEditingController _autoRecordController;
  late TextEditingController _storageQuotaController;

  bool get _isMobilePlatform {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  @override
  void initState() {
    super.initState();
    final configVm = context.read<ConfigModel>();
    _tokenController = TextEditingController(text: configVm.token);
    _distinctIdController = TextEditingController(text: configVm.distinctId);
    _flushIntervalController = TextEditingController(
      text: configVm.flushInterval,
    );
    _autoRecordController = TextEditingController(
      text: configVm.autoRecordPercent,
    );
    _storageQuotaController = TextEditingController(
      text: configVm.storageQuota,
    );

    // Update ViewModel when text changes
    _tokenController.addListener(
      () => configVm.setToken(_tokenController.text),
    );
    _distinctIdController.addListener(
      () => configVm.setDistinctId(_distinctIdController.text),
    );
    _flushIntervalController.addListener(
      () => configVm.setFlushInterval(_flushIntervalController.text),
    );
    _autoRecordController.addListener(
      () => configVm.setAutoRecordPercent(_autoRecordController.text),
    );
    _storageQuotaController.addListener(
      () => configVm.setStorageQuota(_storageQuotaController.text),
    );
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _distinctIdController.dispose();
    _flushIntervalController.dispose();
    _autoRecordController.dispose();
    _storageQuotaController.dispose();
    super.dispose();
  }

  bool _isInitializing = false;

  Future<void> _initialize() async {
    final configVm = context.read<ConfigModel>();

    if (!configVm.validate()) {
      _showError('Please fix validation errors');
      return;
    }

    setState(() => _isInitializing = true);

    try {
      final config = configVm.getConfig();

      // Initialize analytics SDK first so its native broadcast receiver /
      // notification observer is ready before session replay registers
      // the $mp_replay_id super property.
      await MixpanelAnalytics.initialize(
        token: config.token,
        distinctId: config.distinctId,
      );

      final result = await MixpanelSessionReplay.initialize(
        token: config.token,
        distinctId: config.distinctId,
        options: config.toOptions(),
      );

      if (!mounted) return;

      if (result.success) {
        // Set SDK instance
        widget.onSdkInitialized(result.instance);

        // Navigate to home screen
        if (mounted) {
          Navigator.pushReplacementNamed(context, AppRoutes.home);
        }
      } else {
        _showError(result.errorMessage ?? 'Failed to initialize SDK');
      }
    } catch (e) {
      if (mounted) {
        _showError('Error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.pink),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Replay SDK Configuration'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Consumer<ConfigModel>(
        builder: (context, configVm, child) {
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildTextField(
                      controller: _tokenController,
                      label: 'Token',
                      enabled: !_isInitializing,
                      errorText: configVm.tokenError,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _distinctIdController,
                      label: 'Distinct ID',
                      enabled: !_isInitializing,
                      errorText: configVm.distinctIdError,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _flushIntervalController,
                      label: 'Flush Interval (seconds, 0 = disabled)',
                      enabled: !_isInitializing,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                      ),
                      errorText: configVm.flushIntervalError,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _autoRecordController,
                      label: 'Auto Record Sessions %',
                      enabled: !_isInitializing,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      errorText: configVm.autoRecordPercentError,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _storageQuotaController,
                      label: 'Storage Quota (MB)',
                      enabled: !_isInitializing,
                      keyboardType: TextInputType.number,
                      errorText: configVm.storageQuotaError,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Auto-Masking',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildSwitch(
                      label: 'Auto-Mask Text',
                      value: configVm.autoMaskText,
                      onChanged: _isInitializing
                          ? null
                          : configVm.setAutoMaskText,
                      subtitle: 'Automatically mask all text widgets',
                    ),
                    _buildSwitch(
                      label: 'Auto-Mask Images',
                      value: configVm.autoMaskImage,
                      onChanged: _isInitializing
                          ? null
                          : configVm.setAutoMaskImage,
                      subtitle: 'Automatically mask all image widgets',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Note: TextField is always masked for security',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildLogLevelDropdown(configVm, _isInitializing),
                    const SizedBox(height: 16),
                    _buildRemoteSettingsModeDropdown(configVm, _isInitializing),
                    if (_isMobilePlatform) ...[
                      const SizedBox(height: 16),
                      _buildSwitch(
                        label: 'WiFi Only (Mobile)',
                        value: configVm.wifiOnly,
                        onChanged: _isInitializing
                            ? null
                            : configVm.setWifiOnly,
                      ),
                    ],
                    const SizedBox(height: 16),
                    _buildSwitch(
                      label: 'Show Debug Mask Overlay',
                      value: configVm.showDebugMaskOverlay,
                      onChanged: _isInitializing
                          ? null
                          : configVm.setShowDebugMaskOverlay,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isInitializing ? null : _initialize,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isInitializing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Initialize SDK',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required bool enabled,
    TextInputType? keyboardType,
    String? errorText,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildRemoteSettingsModeDropdown(
    ConfigModel configVm,
    bool isInitializing,
  ) {
    const labels = {
      RemoteSettingsMode.disabled: 'Disabled',
      RemoteSettingsMode.strict: 'Strict',
      RemoteSettingsMode.fallback: 'Fallback',
    };

    return DropdownButtonFormField<RemoteSettingsMode>(
      value: configVm.remoteSettingsMode,
      decoration: const InputDecoration(
        labelText: 'Remote Settings Mode',
        border: OutlineInputBorder(),
      ),
      items: RemoteSettingsMode.values.map((mode) {
        return DropdownMenuItem(value: mode, child: Text(labels[mode]!));
      }).toList(),
      onChanged: isInitializing
          ? null
          : (value) {
              if (value != null) configVm.setRemoteSettingsMode(value);
            },
    );
  }

  Widget _buildLogLevelDropdown(ConfigModel configVm, bool isInitializing) {
    return DropdownButtonFormField<LogLevel>(
      value: configVm.logLevel,
      decoration: const InputDecoration(
        labelText: 'Log Level',
        border: OutlineInputBorder(),
      ),
      items: LogLevel.values.map((level) {
        return DropdownMenuItem(
          value: level,
          child: Text(level.name.toUpperCase()),
        );
      }).toList(),
      onChanged: isInitializing
          ? null
          : (value) {
              if (value != null) configVm.setLogLevel(value);
            },
    );
  }

  Widget _buildSwitch({
    required String label,
    required bool value,
    required void Function(bool)? onChanged,
    String? subtitle,
  }) {
    return SwitchListTile(
      title: Text(label),
      subtitle: subtitle != null ? Text(subtitle) : null,
      value: value,
      onChanged: onChanged,
    );
  }
}

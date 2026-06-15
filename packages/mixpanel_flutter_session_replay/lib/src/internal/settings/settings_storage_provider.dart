import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../logger.dart';
import 'remote_settings_result.dart';
import 'sdk_config.dart';

/// Manages persistent storage of remote settings results.
///
/// Caches recording enablement state and SDK config to SharedPreferences
/// so they can be used as fallback values when the network is unavailable.
///
/// Key prefix `mp_sr_flutter_` avoids conflicts with native SDK caches
/// (Android uses `mp_sr_recording_`, iOS uses `mp_sr_recording_settings_`).
class SettingsStorageProvider {
  final String _token;
  final MixpanelLogger _logger;

  static const String _prefsPrefix = 'mp_sr_flutter_';

  String get _recordingEnabledKey => '$_prefsPrefix${_token}_enabled';
  String get _sdkConfigKey => '$_prefsPrefix${_token}_sdk_config';

  SettingsStorageProvider({
    required String token,
    required MixpanelLogger logger,
  }) : _token = token,
       _logger = logger;

  void saveRecordingDisabled() {
    try {
      SharedPreferencesAsync().setBool(_recordingEnabledKey, false);
    } catch (e) {
      _logger.error('Failed to cache recording state: $e');
    }
  }

  void clearRecordingState() {
    try {
      SharedPreferencesAsync().remove(_recordingEnabledKey);
    } catch (e) {
      _logger.error('Failed to clear recording cache: $e');
    }
  }

  Future<bool> getRecordingEnabled() async {
    try {
      final isEnabled = await SharedPreferencesAsync().getBool(
        _recordingEnabledKey,
      );
      if (isEnabled != null) {
        if (!isEnabled) {
          _logger.info('Using cached recording state: disabled');
        }
        return isEnabled;
      }
      _logger.info('No cached recording state, defaulting to enabled');
      return true;
    } catch (e) {
      _logger.error('Failed to check cached recording state: $e');
      return true; // Default to enabled on error
    }
  }

  // --- SDK Config ---

  void saveSdkConfig(SdkConfig sdkConfig) {
    try {
      SharedPreferencesAsync().setString(
        _sdkConfigKey,
        jsonEncode(sdkConfig.toJson()),
      );
    } catch (e) {
      _logger.error('Failed to cache SDK config: $e');
    }
  }

  void clearSdkConfig() {
    try {
      SharedPreferencesAsync().remove(_sdkConfigKey);
    } catch (e) {
      _logger.error('Failed to clear cached SDK config: $e');
    }
  }

  Future<SdkConfig?> getSdkConfig() async {
    try {
      final jsonString = await SharedPreferencesAsync().getString(
        _sdkConfigKey,
      );
      if (jsonString != null) {
        final configJson = jsonDecode(jsonString) as Map<String, dynamic>;
        final config = SdkConfig.fromJson(configJson);
        _logger.info('Using cached SDK config: $jsonString');
        return config;
      }
    } catch (e) {
      _logger.error('Failed to get cached SDK config: $e');
    }
    return null;
  }

  // --- Combined ---

  Future<RemoteSettingsResult> getCachedSettingsResult() async {
    return RemoteSettingsResult(
      isRecordingEnabled: await getRecordingEnabled(),
      sdkConfig: await getSdkConfig(),
      isFromCache: true,
    );
  }
}

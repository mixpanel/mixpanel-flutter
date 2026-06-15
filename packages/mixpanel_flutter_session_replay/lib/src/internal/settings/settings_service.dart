import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../version.dart';
import '../endpoints.dart';
import '../logger.dart';
import 'remote_settings_result.dart';
import 'remote_enablement_state.dart';
import 'sdk_config.dart';
import 'settings_storage_provider.dart';

export 'remote_settings_result.dart';
export 'remote_enablement_state.dart';
export 'sdk_config.dart';

/// Service for fetching remote settings from Mixpanel's settings endpoint.
///
/// Handles the network request to check if session replay recording is enabled
/// (enablement state) and to fetch remote SDK configuration (e.g.,
/// `record_sessions_percent`). The check runs once per app launch.
///
/// Persistent caching is delegated to [SettingsStorageProvider].
class SettingsService {
  final String _token;
  final MixpanelLogger _logger;
  final http.Client _httpClient;
  final SettingsStorageProvider _storageProvider;

  /// Full `/settings` endpoint, derived from the configured base URL.
  final String _endpoint;

  /// Request timeout (5 seconds, matching iOS/Android)
  static const Duration _timeout = Duration(seconds: 5);

  /// Cached result from the last check (in-memory, per app launch)
  RemoteSettingsResult? _cachedResult;

  /// Current remote enablement state.
  RemoteEnablementState get remoteState =>
      switch (_cachedResult?.isRecordingEnabled) {
        true => RemoteEnablementState.enabled,
        false => RemoteEnablementState.disabled,
        null => RemoteEnablementState.pending,
      };

  /// Completer for in-flight settings check
  Completer<RemoteSettingsResult>? _pendingCheck;

  /// Whether this service has been disposed
  bool _isDisposed = false;

  SettingsService({
    required String token,
    required MixpanelLogger logger,
    required SettingsStorageProvider storageProvider,
    required http.Client httpClient,
    String serverUrl = EndPoints.defaultBaseUrl,
  }) : _token = token,
       _logger = logger,
       _httpClient = httpClient,
       _storageProvider = storageProvider,
       _endpoint = EndPoints.settings(serverUrl);

  /// Fetch remote settings including recording status and SDK config.
  ///
  /// This performs a network request to Mixpanel's settings endpoint once per
  /// app launch. Returns a [RemoteSettingsResult] containing both the recording
  /// enablement state and any remote SDK configuration.
  ///
  /// If a check is already in progress, waits for that check to complete.
  /// On failure, returns cached values from SharedPreferences.
  Future<RemoteSettingsResult> fetchRemoteSettings() async {
    // Return cached result if already checked
    if (_cachedResult != null) {
      _logger.debug('Settings already checked, returning cached result');
      return _cachedResult!;
    }

    // If check is already in progress, wait for it to complete
    if (_pendingCheck != null) {
      _logger.debug('Settings check already in progress, waiting...');
      return await _pendingCheck!.future;
    }

    // Create completer for this check
    _pendingCheck = Completer<RemoteSettingsResult>();

    try {
      _logger.debug('Fetching remote settings...');
      final result = await _performRemoteSettingsFetch();
      _cachedResult = result;
      _logger.info(
        'Remote settings check complete: '
        'isEnabled=${result.isRecordingEnabled}, '
        'sdkConfig=${result.sdkConfig != null ? "present" : "null"}, '
        'isFromCache=${result.isFromCache}',
      );
      _pendingCheck!.complete(result);
      return result;
    } catch (e) {
      _logger.warning('Settings fetch failed: $e - using cached values');
      final result = await _storageProvider.getCachedSettingsResult();
      _cachedResult = result;
      _pendingCheck!.complete(result);
      return result;
    } finally {
      _pendingCheck = null;
    }
  }

  /// Backward-compatible method that returns just the recording enabled state.
  ///
  /// Delegates to [fetchRemoteSettings] and extracts the boolean result.
  Future<bool> checkRecordingEnabled() async {
    final result = await fetchRemoteSettings();
    return result.isRecordingEnabled;
  }

  /// Make network request to settings endpoint.
  Future<RemoteSettingsResult> _performRemoteSettingsFetch() async {
    final uri = Uri.parse(_endpoint).replace(
      queryParameters: {
        'recording': '1',
        'sdk_config': '1',
        'mp_lib': 'flutter-sr',
        '\$lib_version': sdkVersion,
        '\$os': operatingSystem,
      },
    );

    final credentials = base64Encode(utf8.encode('$_token:'));
    final authHeader = 'Basic $credentials';

    _logger.debug('GET $uri');

    final response = await _httpClient
        .get(uri, headers: {'Authorization': authHeader})
        .timeout(_timeout);

    _logger.debug('Settings response status: ${response.statusCode}');

    if (response.statusCode == 200) {
      return _handleSuccessResponse(response.body);
    } else {
      throw Exception(
        'Settings request failed with status ${response.statusCode}',
      );
    }
  }

  /// Parse successful settings response.
  RemoteSettingsResult _handleSuccessResponse(String responseBody) {
    _logger.debug('Parsing settings response');
    final json = jsonDecode(responseBody) as Map<String, dynamic>;

    // Parse recording enablement
    final recording = json['recording'] as Map<String, dynamic>?;
    final isEnabled = recording?['is_enabled'] as bool? ?? true;

    if (isEnabled) {
      _logger.info('Recording settings check: enabled');
      _storageProvider.clearRecordingState();
    } else {
      final error = recording?['error'] as String?;
      _logger.warning('Recording settings check: disabled');
      if (error != null) {
        _logger.warning('Recording settings error: $error');
      }
      _storageProvider.saveRecordingDisabled();
    }

    // Parse SDK config
    final sdkConfigWrapper = json['sdk_config'] as Map<String, dynamic>?;
    SdkConfig? sdkConfig;

    if (sdkConfigWrapper != null) {
      final configJson = sdkConfigWrapper['config'] as Map<String, dynamic>?;
      final configError = sdkConfigWrapper['error'] as String?;

      if (configJson != null) {
        sdkConfig = SdkConfig.fromJson(configJson);
        _storageProvider.saveSdkConfig(sdkConfig);
        _logger.info('Remote SDK config: $configJson');
      } else {
        _logger.warning(
          'Remote SDK config not found'
          '${configError != null ? ". Error: $configError" : ""}',
        );
        _storageProvider.clearSdkConfig();
      }
    } else {
      _logger.warning('No sdk_config in settings response');
      _storageProvider.clearSdkConfig();
    }

    return RemoteSettingsResult(
      isRecordingEnabled: isEnabled,
      sdkConfig: sdkConfig,
      isFromCache: false,
    );
  }

  /// Dispose resources
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
  }
}

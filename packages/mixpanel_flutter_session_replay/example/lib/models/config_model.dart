import 'package:flutter/foundation.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';
import '../models/sdk_config.dart';

enum BackgroundBehaviorSelection { pause, stop }

/// ViewModel for configuration screen
class ConfigModel extends ChangeNotifier {
  String _token = const String.fromEnvironment('MIXPANEL_TOKEN');
  String _distinctId = 'flutter_test_user';
  String _flushInterval = '10';
  String _autoRecordPercent = '100.0';
  String _storageQuota = '50';
  LogLevel _logLevel = LogLevel.debug;
  RemoteSettingsMode _remoteSettingsMode = RemoteSettingsMode.disabled;
  bool _wifiOnly = false;
  bool _showDebugMaskOverlay = false;
  bool _autoMaskText = true;
  bool _autoMaskImage = true;
  bool _enableWireframes = false;
  bool _enableWireframeDebugEmitter = true;
  bool _useAccessibilityLabelFallback = false;
  BackgroundBehaviorSelection _backgroundBehavior = kIsWeb
      ? BackgroundBehaviorSelection.pause
      : BackgroundBehaviorSelection.stop;
  String _backgroundPauseIdleSeconds = '1800';
  // Overridable at launch so integration tests and manual runs can reach the
  // idle-out and max-duration paths without retyping the fields each time:
  //   flutter run --dart-define=WEB_IDLE_TIMEOUT_SECONDS=60
  String _webIdleTimeoutSeconds = const String.fromEnvironment(
    'WEB_IDLE_TIMEOUT_SECONDS',
    defaultValue: '1800',
  );
  String _webMaxSessionSeconds = const String.fromEnvironment(
    'WEB_MAX_SESSION_SECONDS',
    defaultValue: '86400',
  );

  String? _tokenError;
  String? _distinctIdError;
  String? _flushIntervalError;
  String? _autoRecordPercentError;
  String? _storageQuotaError;
  String? _webIdleTimeoutError;
  String? _webMaxSessionError;
  String? _backgroundPauseIdleError;

  // Getters
  String get token => _token;
  String get distinctId => _distinctId;
  String get flushInterval => _flushInterval;
  String get autoRecordPercent => _autoRecordPercent;
  String get storageQuota => _storageQuota;
  LogLevel get logLevel => _logLevel;
  RemoteSettingsMode get remoteSettingsMode => _remoteSettingsMode;
  bool get wifiOnly => _wifiOnly;
  bool get showDebugMaskOverlay => _showDebugMaskOverlay;
  bool get autoMaskText => _autoMaskText;
  bool get autoMaskImage => _autoMaskImage;
  bool get enableWireframes => _enableWireframes;
  bool get enableWireframeDebugEmitter => _enableWireframeDebugEmitter;
  bool get useAccessibilityLabelFallback => _useAccessibilityLabelFallback;
  BackgroundBehaviorSelection get backgroundBehavior => _backgroundBehavior;
  String get backgroundPauseIdleSeconds => _backgroundPauseIdleSeconds;
  String get webIdleTimeoutSeconds => _webIdleTimeoutSeconds;
  String get webMaxSessionSeconds => _webMaxSessionSeconds;

  String? get tokenError => _tokenError;
  String? get distinctIdError => _distinctIdError;
  String? get flushIntervalError => _flushIntervalError;
  String? get autoRecordPercentError => _autoRecordPercentError;
  String? get storageQuotaError => _storageQuotaError;
  String? get webIdleTimeoutError => _webIdleTimeoutError;
  String? get webMaxSessionError => _webMaxSessionError;
  String? get backgroundPauseIdleError => _backgroundPauseIdleError;

  // Setters
  void setToken(String value) {
    _token = value;
    _tokenError = null;
    notifyListeners();
  }

  void setDistinctId(String value) {
    _distinctId = value;
    _distinctIdError = null;
    notifyListeners();
  }

  void setFlushInterval(String value) {
    _flushInterval = value;
    _flushIntervalError = null;
    notifyListeners();
  }

  void setAutoRecordPercent(String value) {
    _autoRecordPercent = value;
    _autoRecordPercentError = null;
    notifyListeners();
  }

  void setStorageQuota(String value) {
    _storageQuota = value;
    _storageQuotaError = null;
    notifyListeners();
  }

  void setWebIdleTimeoutSeconds(String value) {
    _webIdleTimeoutSeconds = value;
    _webIdleTimeoutError = null;
    notifyListeners();
  }

  void setWebMaxSessionSeconds(String value) {
    _webMaxSessionSeconds = value;
    _webMaxSessionError = null;
    notifyListeners();
  }

  void setBackgroundBehavior(BackgroundBehaviorSelection value) {
    _backgroundBehavior = value;
    if (value == BackgroundBehaviorSelection.stop) {
      _backgroundPauseIdleError = null;
    }
    notifyListeners();
  }

  void setBackgroundPauseIdleSeconds(String value) {
    _backgroundPauseIdleSeconds = value;
    _backgroundPauseIdleError = null;
    notifyListeners();
  }

  void setLogLevel(LogLevel value) {
    _logLevel = value;
    notifyListeners();
  }

  void setRemoteSettingsMode(RemoteSettingsMode value) {
    _remoteSettingsMode = value;
    notifyListeners();
  }

  void setWifiOnly(bool value) {
    _wifiOnly = value;
    notifyListeners();
  }

  void setShowDebugMaskOverlay(bool value) {
    _showDebugMaskOverlay = value;
    notifyListeners();
  }

  void setAutoMaskText(bool value) {
    _autoMaskText = value;
    notifyListeners();
  }

  void setAutoMaskImage(bool value) {
    _autoMaskImage = value;
    notifyListeners();
  }

  void setEnableWireframes(bool value) {
    _enableWireframes = value;
    notifyListeners();
  }

  void setEnableWireframeDebugEmitter(bool value) {
    _enableWireframeDebugEmitter = value;
    notifyListeners();
  }

  void setUseAccessibilityLabelFallback(bool value) {
    _useAccessibilityLabelFallback = value;
    notifyListeners();
  }

  /// Validate all fields
  bool validate() {
    bool isValid = true;

    // Validate token
    if (_token.trim().isEmpty) {
      _tokenError = 'Token is required';
      isValid = false;
    }

    // Validate distinct ID
    if (_distinctId.trim().isEmpty) {
      _distinctIdError = 'Distinct ID is required';
      isValid = false;
    }

    // Validate flush interval
    final flushIntervalInt = int.tryParse(_flushInterval);
    if (flushIntervalInt == null) {
      _flushIntervalError = 'Must be a number';
      isValid = false;
    }

    // Validate auto record percent
    final autoRecordDouble = double.tryParse(_autoRecordPercent);
    if (autoRecordDouble == null ||
        autoRecordDouble < 0 ||
        autoRecordDouble > 100) {
      _autoRecordPercentError = 'Must be between 0 and 100';
      isValid = false;
    }

    // Validate web idle timeout (0 disables it)
    final idleSeconds = int.tryParse(_webIdleTimeoutSeconds);
    if (idleSeconds == null || idleSeconds < 0) {
      _webIdleTimeoutError = 'Must be 0 or greater';
      isValid = false;
    }

    // Validate web max session duration (0 would expire every session at once)
    final maxSeconds = int.tryParse(_webMaxSessionSeconds);
    if (maxSeconds == null || maxSeconds <= 0) {
      _webMaxSessionError = 'Must be a positive number';
      isValid = false;
    }

    if (_backgroundBehavior == BackgroundBehaviorSelection.pause) {
      final pauseIdleSeconds = int.tryParse(_backgroundPauseIdleSeconds);
      if (pauseIdleSeconds == null || pauseIdleSeconds <= 0) {
        _backgroundPauseIdleError = 'Must be a positive number';
        isValid = false;
      }
    }

    // Validate storage quota
    final storageQuotaInt = int.tryParse(_storageQuota);
    if (storageQuotaInt == null || storageQuotaInt <= 0) {
      _storageQuotaError = 'Must be a positive number';
      isValid = false;
    }

    notifyListeners();
    return isValid;
  }

  /// Get configuration from current values
  SdkConfig getConfig() {
    final backgroundBehavior = switch (_backgroundBehavior) {
      BackgroundBehaviorSelection.pause => ReplayBackgroundBehavior.pause(
        idleTimeout: Duration(seconds: int.parse(_backgroundPauseIdleSeconds)),
      ),
      BackgroundBehaviorSelection.stop => ReplayBackgroundBehavior.stop,
    };

    return SdkConfig(
      token: _token.trim(),
      distinctId: _distinctId.trim(),
      flushInterval: int.parse(_flushInterval),
      autoRecordPercent: double.parse(_autoRecordPercent),
      storageQuota: int.parse(_storageQuota),
      logLevel: _logLevel,
      remoteSettingsMode: _remoteSettingsMode,
      wifiOnly: _wifiOnly,
      showDebugMaskOverlay: _showDebugMaskOverlay,
      autoMaskText: _autoMaskText,
      autoMaskImage: _autoMaskImage,
      enableWireframes: _enableWireframes,
      enableWireframeDebugEmitter: _enableWireframeDebugEmitter,
      useAccessibilityLabelFallback: _useAccessibilityLabelFallback,
      backgroundBehavior: backgroundBehavior,
      webIdleTimeoutSeconds: int.parse(_webIdleTimeoutSeconds),
      webMaxSessionSeconds: int.parse(_webMaxSessionSeconds),
    );
  }
}

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';

/// Configuration data for SDK initialization
class SdkConfig {
  SdkConfig({
    required this.token,
    required this.distinctId,
    required this.flushInterval,
    required this.autoRecordPercent,
    required this.storageQuota,
    required this.logLevel,
    required this.remoteSettingsMode,
    required this.wifiOnly,
    required this.showDebugMaskOverlay,
    required this.autoMaskText,
    required this.autoMaskImage,
  });

  final String token;
  final String distinctId;
  final int flushInterval; // seconds
  final double autoRecordPercent; // 0-100
  final int storageQuota; // MB
  final LogLevel logLevel;
  final RemoteSettingsMode remoteSettingsMode;
  final bool wifiOnly;
  final bool showDebugMaskOverlay;
  final bool autoMaskText;
  final bool autoMaskImage;

  /// Default configuration
  factory SdkConfig.defaultConfig() {
    return SdkConfig(
      token: const String.fromEnvironment('MIXPANEL_TOKEN'),
      distinctId: 'flutter_test_user',
      flushInterval: 10,
      autoRecordPercent: 100.0,
      storageQuota: 50,
      logLevel: LogLevel.debug,
      remoteSettingsMode: RemoteSettingsMode.disabled,
      wifiOnly: false,
      showDebugMaskOverlay: false,
      autoMaskText: true,
      autoMaskImage: true,
    );
  }

  /// Check if platform is mobile (Android or iOS)
  static bool get isMobilePlatform {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Convert to SessionReplayOptions
  SessionReplayOptions toOptions() {
    // Build auto-masked views set based on toggles
    final autoMaskedViews = <AutoMaskedView>{};
    if (autoMaskText) autoMaskedViews.add(AutoMaskedView.text);
    if (autoMaskImage) autoMaskedViews.add(AutoMaskedView.image);

    return SessionReplayOptions(
      autoMaskedViews: autoMaskedViews,
      logLevel: logLevel,
      flushInterval: Duration(seconds: flushInterval),
      autoRecordSessionsPercent: autoRecordPercent,
      remoteSettingsMode: remoteSettingsMode,
      storageQuotaMB: storageQuota,
      platformOptions: PlatformOptions(
        mobile: MobileOptions(wifiOnly: wifiOnly),
      ),
      debugOptions: showDebugMaskOverlay ? const DebugOptions() : null,
    );
  }
}

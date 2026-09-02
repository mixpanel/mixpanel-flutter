import 'package:flutter/services.dart';

/// Host app identity, read from the platform via the native plugin.
///
/// Sent as query parameters on the `/settings` request so the Mixpanel backend
/// can apply server-side SDK blocking per app ID and app build version.
///
/// `buildNumber` deliberately carries the platform's *build* identifier rather
/// than the user-facing version string, matching the native SDKs:
/// `CFBundleVersion` on iOS/macOS and `versionCode` on Android.
class AppInfo {
  static const _channel = MethodChannel('com.mixpanel.flutter_session_replay');

  const AppInfo({this.bundleId, this.buildNumber});

  /// The host app's bundle/package identifier, or null if unavailable.
  final String? bundleId;

  /// The host app's build number, or null if unavailable.
  final String? buildNumber;

  /// Reads the host app's bundle ID and build number from the platform.
  ///
  /// Returns an [AppInfo] with null fields when the values cannot be read —
  /// for example on a platform without the plugin registered, as in unit
  /// tests. Callers omit the corresponding query parameters in that case.
  static Future<AppInfo> fromPlatform() async {
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>(
        'getAppInfo',
      );
      return AppInfo(
        bundleId: info?['bundleId'] as String?,
        buildNumber: info?['buildNumber'] as String?,
      );
    } catch (_) {
      // Best-effort — the params are omitted when the platform can't supply them
      return const AppInfo();
    }
  }
}

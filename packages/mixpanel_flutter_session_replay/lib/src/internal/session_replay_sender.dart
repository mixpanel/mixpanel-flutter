import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

/// Integrates Session Replay data with the main Mixpanel event tracking SDK.
///
/// Uses native platform channels to register/unregister super properties
/// via the same mechanisms the native Session Replay SDKs use:
/// - Android: Sends a broadcast intent (`com.mixpanel.properties.register`)
///   that the main Mixpanel Android SDK listens for via BroadcastReceiver.
/// - iOS: Posts a NotificationCenter notification
///   (`com.mixpanel.properties.register`) that the main Mixpanel iOS SDK
///   observes.
///
/// Since `mixpanel_flutter` wraps these native SDKs, the registered super
/// properties automatically flow through to all tracked events.
///
/// On web and macOS, those native bridges do not exist. Calls are instead sent
/// to the `mixpanel_flutter` plugin's existing super-property methods, which
/// delegate to the platform Mixpanel SDK.
class SessionReplaySender {
  SessionReplaySender._();

  static const _channelTimeout = Duration(seconds: 1);
  static const _sessionReplayChannel = MethodChannel(
    'com.mixpanel.flutter_session_replay',
  );
  static const _mixpanelFlutterChannel = MethodChannel('mixpanel_flutter');

  static bool get _usesMixpanelFlutterChannel =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.macOS;

  /// Register super properties with the main Mixpanel SDK via native IPC.
  ///
  /// Called when recording starts to attach `$mp_replay_id` to all events.
  /// On Android, sends a broadcast intent. On iOS, posts a notification.
  static Future<void> register(Map<String, dynamic> properties) async {
    try {
      if (_usesMixpanelFlutterChannel) {
        await _mixpanelFlutterChannel
            .invokeMethod<void>('registerSuperProperties', {
              'properties': properties,
            })
            .timeout(_channelTimeout);
      } else {
        await _sessionReplayChannel
            .invokeMethod<void>('registerSuperProperties', properties)
            .timeout(_channelTimeout);
      }
    } catch (_) {
      // Best-effort — don't crash the host app if the channel call fails
    }
  }

  /// Unregister a super property from the main Mixpanel SDK via native IPC.
  ///
  /// Called when recording stops to remove `$mp_replay_id` from events.
  /// On Android, sends an unregister broadcast. On iOS, posts an unregister
  /// notification.
  static Future<void> unregister(String propertyName) async {
    try {
      if (_usesMixpanelFlutterChannel) {
        await _mixpanelFlutterChannel
            .invokeMethod<void>('unregisterSuperProperty', {
              'propertyName': propertyName,
            })
            .timeout(_channelTimeout);
      } else {
        await _sessionReplayChannel
            .invokeMethod<void>('unregisterSuperProperty', {
              'key': propertyName,
            })
            .timeout(_channelTimeout);
      }
    } catch (_) {
      // Best-effort — don't crash the host app if the channel call fails
    }
  }
}

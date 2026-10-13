import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web implementation of the MixpanelSessionReplay plugin.
///
/// Registers a no-op MethodChannel handler so that platform channel calls
/// (compressImage, background task calls, etc.) succeed silently on web
/// instead of throwing MissingPluginException. Replay super properties are
/// sent directly to the `mixpanel_flutter` channel by SessionReplaySender.
class MixpanelSessionReplayPluginWeb {
  static void registerWith(Registrar registrar) {
    final channel = MethodChannel(
      'com.mixpanel.flutter_session_replay',
      const StandardMethodCodec(),
      registrar,
    );
    channel.setMethodCallHandler(_handleMethodCall);
  }

  /// The native-only calls that legitimately reach this channel on web.
  static const _webNoOps = {
    'getAppInfo',
    'beginBackgroundTask',
    'endBackgroundTask',
    'disposeCache',
  };

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (_webNoOps.contains(call.method)) return null;
    // Anything else reaching web is a routing mistake. Returning null for it
    // would let the caller treat a call that never ran as having succeeded.
    throw PlatformException(
      code: 'Unimplemented',
      message:
          '${call.method} is not implemented on web for '
          'com.mixpanel.flutter_session_replay',
    );
  }
}

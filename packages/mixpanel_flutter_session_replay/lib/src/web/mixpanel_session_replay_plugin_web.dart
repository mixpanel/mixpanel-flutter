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

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    // All methods are no-ops on web
    return null;
  }
}

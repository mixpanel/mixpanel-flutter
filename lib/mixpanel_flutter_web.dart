import 'dart:async';
// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html show window;

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:mixpanel_flutter/web/mixpanel_js_bindings.dart';

/// A web implementation of the MixpanelFlutter plugin.
class MixpanelFlutterPlugin {
  static void registerWith(Registrar registrar) {
    final MethodChannel channel = MethodChannel(
      'mixpanel_flutter',
      const StandardMethodCodec(),
      registrar,
    );

    final pluginInstance = MixpanelFlutterPlugin();
    channel.setMethodCallHandler(pluginInstance.handleMethodCall);
  }

  /// Handles method calls over the MethodChannel of this plugin.
  /// Note: Check the "federated" architecture for a new way of doing this:
  /// https://flutter.dev/go/federated-plugins
  Future<dynamic> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'getPlatformVersion':
        return getPlatformVersion();
      case 'initialize':
        initialize(call);
        break;
      case 'track':
        var args = call.arguments as Map<Object?, Object?>;
        var eventName = args['eventName'] as String;
        track(eventName);
        break;
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details:
              'mixpanel_flutter for web doesn\'t implement \'${call.method}\'',
        );
    }
  }

  void initialize(MethodCall call) {
    var args = call.arguments as Map<Object?, Object?>;
    var token = args['token'] as String;

    print(args);
    init(token);
  }

  /// Returns a [String] containing the version of the platform.
  Future<String> getPlatformVersion() {
    final version = html.window.navigator.userAgent;
    return Future.value(version);
  }
}

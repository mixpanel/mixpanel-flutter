import 'dart:io' show Platform;

import 'package:mixpanel_flutter/mixpanel_flutter.dart';

/// Wrapper around the Mixpanel Flutter Analytics SDK.
///
/// Compartmentalizes all analytics calls and no-ops on unsupported platforms
/// (web, Linux, Windows) so the rest of the app doesn't need platform checks.
class MixpanelAnalytics {
  MixpanelAnalytics._(this._mixpanel);

  final Mixpanel? _mixpanel;

  static MixpanelAnalytics? _instance;

  /// The shared instance. Returns null if not yet initialized.
  static MixpanelAnalytics? get instance => _instance;

  static bool get _isSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  /// Initialize the analytics SDK. No-ops on unsupported platforms.
  static Future<void> initialize({
    required String token,
    required String distinctId,
  }) async {
    if (!_isSupported) {
      _instance = MixpanelAnalytics._(null);
      return;
    }

    final mixpanel = await Mixpanel.init(token, trackAutomaticEvents: false);
    mixpanel.identify(distinctId);
    mixpanel.setLoggingEnabled(true);
    _instance = MixpanelAnalytics._(mixpanel);
  }

  /// Track an event with optional properties.
  void track(String eventName, {Map<String, dynamic>? properties}) {
    _mixpanel?.track(eventName, properties: properties);
    _mixpanel?.flush();
  }

  /// Flush queued events.
  void flush() {
    _mixpanel?.flush();
  }
}

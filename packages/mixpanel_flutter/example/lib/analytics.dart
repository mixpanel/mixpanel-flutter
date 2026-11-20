import 'package:mixpanel_flutter/mixpanel_flutter.dart';

class MixpanelManager {
  static Mixpanel? _instance;

  static Future<Mixpanel> init() async {
    if (_instance == null) {
      _instance = await Mixpanel.init("YOUR_PROJECT_TOKEN",
          optOutTrackingDefault: false,
          trackAutomaticEvents: true,
          featureFlags: FeatureFlagsConfig(enabled: true),
          autocaptureOptions: const AutocaptureOptions(
            clickOptions: ClickOptions(),
            rageClickOptions: RageClickOptions(),
            deadClickOptions: DeadClickOptions(),
          ));
      _instance?.setLoggingEnabled(true);
    }
    return _instance!;
  }

  // Mixpanel.init replaces the native instance that every Dart handle calls, so
  // a page that initializes its own project calls this when it closes
  static Future<void> restore() async {
    if (_instance != null) {
      _instance = null;
      await init();
    }
  }
}

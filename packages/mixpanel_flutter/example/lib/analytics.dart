import 'package:mixpanel_flutter/mixpanel_flutter.dart';

class MixpanelManager {
  static Mixpanel? _instance;

  static Future<Mixpanel> init() async {
    if (_instance == null) {
      _instance = await Mixpanel.init("YOUR_PROJECT_TOKEN",
          optOutTrackingDefault: false,
          trackAutomaticEvents: true,
          autocaptureOptions: const AutocaptureOptions(
            clickOptions: ClickOptions(),
            rageClickOptions: RageClickOptions(),
            deadClickOptions: DeadClickOptions(),
          ),
          featureFlags: const FeatureFlagsConfig(enabled: true));
      _instance?.setLoggingEnabled(true);
    }
    return _instance!;
  }
}

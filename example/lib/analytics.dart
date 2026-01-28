import 'package:mixpanel_flutter/mixpanel_flutter.dart';

class MixpanelManager {
  static Mixpanel? _instance;

  static Future<Mixpanel> init() async {
    if (_instance == null) {
      _instance = await Mixpanel.init("metrics-1",
          optOutTrackingDefault: false,
          trackAutomaticEvents: true,
          featureFlags: FeatureFlagsConfig(enabled: true));
      _instance?.setLoggingEnabled(true);
    }
    return _instance!;
  }
}

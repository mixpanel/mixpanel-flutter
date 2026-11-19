import 'package:mixpanel_flutter/mixpanel_flutter.dart';

class MixpanelManager {
  static Mixpanel? _instance;

  static Future<Mixpanel> init() async {
    if (_instance == null) {
      _instance = await Mixpanel.init("YOUR_PROJECT_TOKEN",
          optOutTrackingDefault: false,
          trackAutomaticEvents: true,
          // Applied before the first flush on every launch. Set to false to
          // stop Mixpanel using the client IP address for geolocation.
          useIpAddressForGeolocation: true,
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
}

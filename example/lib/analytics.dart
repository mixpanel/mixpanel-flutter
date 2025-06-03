import 'package:mixpanel_flutter/mixpanel_flutter.dart';

class MixpanelManager {
  static Mixpanel? _instance;

  static Future<Mixpanel> init() async {
    if (_instance == null) {
      _instance = await Mixpanel.init("6d83a31dc1373e3153a5a3d087084721",
          optOutTrackingDefault: false, trackAutomaticEvents: true);
      _instance?.setLoggingEnabled(true);
    }
    return _instance!;
  }
}

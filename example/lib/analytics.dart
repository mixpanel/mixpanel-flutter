import 'package:mixpanel_flutter/mixpanel_flutter.dart';

class MixpanelManager {
  static Mixpanel? _instance;

  static Future<Mixpanel> init() async {
    if (_instance == null) {
      _instance = await Mixpanel.init("5d9d3df08d1c34a272abf23d892820bf",
          optOutTrackingDefault: false, trackAutomaticEvents: true);
      _instance?.setFlushBatchSize(3);
      _instance?.setLoggingEnabled(true);
    }
    return _instance!;
  }
}

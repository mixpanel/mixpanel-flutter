import 'package:mixpanel_flutter/mixpanel_flutter.dart';

class MixpanelManager {

  Mixpanel instance;

  static MixpanelManager _instance;

  MixpanelManager._internal() {
    if (instance == null) {
      this._initMixpanel();
    }
    _instance = this;
  }

  factory MixpanelManager() => _instance ?? MixpanelManager._internal();


  Future<void> _initMixpanel() async {
    instance = await Mixpanel.init("5d9d3df08d1c34a272abf23d892820bf",
        optOutTrackingDefault: false);
  }

}
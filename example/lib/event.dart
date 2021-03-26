import 'analytics.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mixpanel_flutter_example/widget.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';

class EventScreen extends StatefulWidget {
  @override
  _EventScreenState createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  late final Mixpanel _mixpanel;

  @override
  initState() {
    super.initState();
    _initMixpanel();
  }

  Future<void> _initMixpanel() async {
    _mixpanel = await MixpanelManager.init();
  }

  void _showAlert(BuildContext context, String title, String alertText) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(title),
              content: Text(alertText),
            ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xff4f44e0),
        title: Text("Event"),
      ),
      body: Center(
          child: ListView(
        children: [
          SizedBox(
            height: 40,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Track w/o Properties',
              onPressed: () {
                _mixpanel.track("Track Event!");
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Track with Properties',
              onPressed: () {
                _mixpanel.track("Track event with property", properties: {
                  "Cool Property": "Property Value",
                  "test": 233,
                  "complex": {
                    "child": [1, 2]
                  }
                });
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Identify',
              onPressed: () {
                _mixpanel.identify("testDistinctId3");
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Time Event 2 secs',
              onPressed: () {
                String eventName = "Timed Event";
                _mixpanel.timeEvent(eventName);
                Timer(Duration(seconds: 2), () {
                  _mixpanel.track(eventName);
                });
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
                text: 'Get Current SuperProperties',
                onPressed: () async {
                  String jsonString =
                      jsonEncode(await _mixpanel.getSuperProperties());
                  _showAlert(context, "Super Properties", jsonString);
                }),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Clear SuperProperties',
              onPressed: () {
                _mixpanel.clearSuperProperties();
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Register SuperProperties',
              onPressed: () {
                _mixpanel.registerSuperProperties({
                  "super property": "super property value",
                  "super property1": "super property value1",
                });
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Register SuperProperties Once',
              onPressed: () {
                _mixpanel.registerSuperPropertiesOnce(
                    {"super property": "super property value1"});
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Unregister SuperProperty',
              onPressed: () {
                _mixpanel.unregisterSuperProperty("super property");
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Flush',
              onPressed: () {
                _mixpanel.flush();
              },
            ),
          ),
          SizedBox(
            height: 40,
          ),
        ],
      )),
    );
  }
}

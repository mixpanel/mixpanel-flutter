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
    final width = MediaQuery.of(context).size.width;
    final defaultWidth = width * 0.65;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xff4f44e0),
        title: const Text("Event"),
      ),
      body: Center(
          child: ListView(
        children: [
          const SizedBox(height: 40),
          SizedBox(
            width: defaultWidth,
            child: MixpanelButton(
              text: 'Track w/o Properties',
              onPressed: () {
                _mixpanel.track("Track Event!");
              },
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: defaultWidth,
            child: MixpanelButton(
              text: 'Track with Properties',
              onPressed: () {
                _mixpanel.track("Track event with property", properties: {
                  "Cool Property": "Property Value",
                  "test": 233,
                  "complex": {
                    "child": [
                      {"deep1": "value1"},
                      {
                        "deep2": [1, 2]
                      }
                    ]
                  },
                  "date": DateTime.now(),
                  "uri": Uri.parse("https://mixpanel.com")
                });
              },
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: defaultWidth,
            child: MixpanelButton(
              text: 'Identify',
              onPressed: () {
                _mixpanel.identify("testDistinctId3");
              },
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: defaultWidth,
            child: MixpanelButton(
              text: 'Get Distinct ID',
              onPressed: () async {
                String? distinctId = await _mixpanel.getDistinctId();
                Widget okButton = TextButton(
                  child: const Text("OK"),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                );
                AlertDialog alert = AlertDialog(
                  title: const Text("Result"),
                  content: Text("${distinctId}"),
                  actions: [
                    okButton,
                  ],
                );

                // show the dialog
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return alert;
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: defaultWidth,
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
          const SizedBox(height: 20),
          SizedBox(
            width: defaultWidth,
            child: MixpanelButton(
                text: 'Get Current SuperProperties',
                onPressed: () async {
                  String jsonString =
                      jsonEncode(await _mixpanel.getSuperProperties());
                  _showAlert(context, "Super Properties", jsonString);
                }),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: defaultWidth,
            child: MixpanelButton(
              text: 'Clear SuperProperties',
              onPressed: () {
                _mixpanel.clearSuperProperties();
              },
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: defaultWidth,
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
          const SizedBox(height: 20),
          SizedBox(
            width: defaultWidth,
            child: MixpanelButton(
              text: 'Register SuperProperties Once',
              onPressed: () {
                _mixpanel.registerSuperPropertiesOnce(
                    {"super property": "super property value1"});
              },
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: defaultWidth,
            child: MixpanelButton(
              text: 'Unregister SuperProperty',
              onPressed: () {
                _mixpanel.unregisterSuperProperty("super property");
              },
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: defaultWidth,
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

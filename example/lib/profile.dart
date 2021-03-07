import 'analytics.dart';
import 'package:flutter/material.dart';
import 'package:mixpanel_flutter_example/widget.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final Mixpanel _mixpanel;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    _initMixpanel();
  }

  Future<void> _initMixpanel() async {
    _mixpanel = await MixpanelManager.init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xff4f44e0),
        title: Text("Profile"),
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
              text: 'Create Alias',
              onPressed: () {
                _mixpanel.alias("New Alias", "testDistinctId");
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Reset',
              onPressed: () {
                _mixpanel.reset();
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Set One Property',
              onPressed: () {
                _mixpanel.getPeople().set("ab", 3);
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Set Properties Once',
              onPressed: () {
                _mixpanel.getPeople().setOnce("a", "a just once");
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Unset Properties',
              onPressed: () {
                _mixpanel.getPeople().unset("a");
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Increment Property',
              onPressed: () {
                _mixpanel.getPeople().increment("a", 1.2);
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Remove Property Value',
              onPressed: () {
                _mixpanel.getPeople().remove("e", "Hello1");
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Append Properties',
              onPressed: () {
                _mixpanel.getPeople().append("e", "Hello1");
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Union Properties',
              onPressed: () {
                _mixpanel.getPeople().union("c", ["goodbye", "hi"]);
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Track Charge w/o Properties',
              onPressed: () {
                _mixpanel.getPeople().trackCharge(22.8);
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Track Charge w Properties',
              onPressed: () {
                _mixpanel
                    .getPeople()
                    .trackCharge(22.8, properties: {"sandwich": 1});
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Clear Charges',
              onPressed: () {
                _mixpanel.getPeople().clearCharges();
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Delete User',
              onPressed: () {
                _mixpanel.getPeople().deleteUser();
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

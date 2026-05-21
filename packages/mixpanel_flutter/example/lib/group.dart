import 'analytics.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:mixpanel_flutter_example/widget.dart';

class GroupScreen extends StatefulWidget {
  @override
  _GroupScreenState createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  late final Mixpanel _mixpanel;
  late final MixpanelGroup _mixpanelGroup;

  @override
  void initState() {
    super.initState();
    _initMixpanel();
  }

  Future<void> _initMixpanel() async {
    _mixpanel = await MixpanelManager.init();
    _mixpanelGroup = _mixpanel.getGroup("company_id", 12346);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xff4f44e0),
        title: Text("Group"),
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
              text: 'Set One Property',
              onPressed: () {
                _mixpanelGroup.set("prop_key", "prop_value");
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
                _mixpanelGroup.setOnce("prop_key_once", "prop_value");
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Unset Property',
              onPressed: () {
                _mixpanelGroup.unset("prop_key");
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Remove Property',
              onPressed: () {
                _mixpanelGroup.remove("prop_key2", "aaa");
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
                _mixpanelGroup.union("prop_key2", ["aaa", "bbb"]);
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Delete Group',
              onPressed: () {
                _mixpanel.deleteGroup("company_id", 12346);
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Set Group',
              onPressed: () {
                _mixpanel.setGroup("company_id", 12346);
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Add Group',
              onPressed: () {
                _mixpanel.addGroup("company_id", 12346);
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Remove Group',
              onPressed: () {
                _mixpanel.removeGroup("company_id", 12346);
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Track with Groups',
              onPressed: () {
                _mixpanel.trackWithGroups("tracked with groups",
                    {"a": 1, "b": 2.3}, {"company_id": 12346});
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

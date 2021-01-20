import 'analytics.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:mixpanel_flutter_example/widget.dart';

class GroupScreen extends StatefulWidget {
  @override
  _GroupScreenState createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {

  MixpanelManager mixpanelManager;
  MixpanelGroup _mixpanelGroup;

  @override
  void initState() {
    super.initState();
    mixpanelManager = MixpanelManager();
    _mixpanelGroup = mixpanelManager.instance.getGroup("company_id", 12345);
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
                    _mixpanelGroup.setOnce("prop_key", "prop_value");
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
                    _mixpanelGroup.unset("aaa");
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
                    _mixpanelGroup.remove("prop_key", "334");
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
                    _mixpanelGroup.union("prop_key", ["prop_value_a", "prop_value_b"]);
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
                    mixpanelManager.instance.deleteGroup("company_id", 12345);
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
                    mixpanelManager.instance.setGroup("company_id", 12345);
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
                    mixpanelManager.instance.setGroup("company_id", 111);
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
                    _mixpanelGroup.remove("prop_key", "334");
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
                    mixpanelManager.instance.trackWithGroups("tracked with groups", {"a": 1, "b": 2.3}, {"company_id": "Mixpanel"});
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
                    mixpanelManager.instance.flush();
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

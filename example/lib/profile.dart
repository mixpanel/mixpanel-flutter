import 'analytics.dart';
import 'package:flutter/material.dart';
import 'package:mixpanel_flutter_example/widget.dart';

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {

  MixpanelManager mixpanelManager;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    mixpanelManager = MixpanelManager();
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
                    mixpanelManager.instance.alias("New Alias", "testDistinctId");
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
                    mixpanelManager.instance.reset();
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
                    mixpanelManager.instance.getPeople().set("d", "yo");
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
                    mixpanelManager.instance.getPeople().setOnce("c", "just once");
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
                    mixpanelManager.instance.getPeople().unset("a");
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
                    mixpanelManager.instance.getPeople().increment("a", 1.2);
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
                    mixpanelManager.instance.getPeople().remove("c", 5);
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
                    mixpanelManager.instance.getPeople().append("e", "Hello");
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
                    mixpanelManager.instance.getPeople().union("a", ["goodbye", "hi"]);
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
                    mixpanelManager.instance.getPeople().trackCharge(22.8);
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
                    mixpanelManager.instance.getPeople().trackCharge(22.8, properties: {"sandwich": 1});
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
                    mixpanelManager.instance.getPeople().clearCharges();
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
                    mixpanelManager.instance.getPeople().deleteUser();
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


import 'analytics.dart';
import 'package:flutter/material.dart';
import 'package:mixpanel_flutter_example/widget.dart';


class GDPRScreen extends StatefulWidget {
  @override
  _GDPRScreenState createState() => _GDPRScreenState();
}

class _GDPRScreenState extends State<GDPRScreen> {

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
        title: Text("GDPR"),
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
                  text: 'Opt In',
                  onPressed: () {
                    mixpanelManager.instance.optInTracking();
                  },
                ),
              ),
              SizedBox(
                height: 20,
              ),
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.65,
                child: MixpanelButton(
                  text: 'Opt Out',
                  onPressed: () {
                    mixpanelManager.instance.optOutTracking();
                  },
                ),
              ),
            ],
          )),
    );
  }
}



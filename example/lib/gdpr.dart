import 'package:flutter/material.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:mixpanel_flutter_example/widget.dart';

class GDPRScreen extends StatefulWidget {
  @override
  _GDPRScreenState createState() => _GDPRScreenState();
}

class _GDPRScreenState extends State<GDPRScreen> {
  final Mixpanel _mixpanel = Mixpanel.instance;

  void showAlertDialog(BuildContext context, bool? result) {
    Widget okButton = TextButton(
      child: Text("OK"),
      onPressed: () {
        Navigator.of(context).pop();
      },
    );

    AlertDialog alert = AlertDialog(
      title: Text("Result"),
      content: Text("${result}"),
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
                _mixpanel.optInTracking();
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
                _mixpanel.optOutTracking();
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Has opted out',
              onPressed: () async {
                bool? optedOut = await _mixpanel.hasOptedOutTracking();
                showAlertDialog(context, optedOut);
              },
            ),
          ),
        ],
      )),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:mixpanel_flutter_example/widget.dart';

import 'event.dart';
import 'gdpr.dart';
import 'group.dart';
import 'profile.dart';

// This is the main page only, check out the example app in https://github.com/mixpanel/mixpanel-flutter/tree/main/example
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Mixpanel.init(
    '<YOUR-MIXPANEL-TOKEN>',
    optOutTrackingDefault: false,
  );

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    initialRoute: '/',
    routes: {
      '/': (context) => FirstScreen(),
      '/event': (context) => EventScreen(),
      '/profile': (context) => ProfileScreen(),
      '/gdpr': (context) => GDPRScreen(),
      '/group': (context) => GroupScreen(),
    },
  ));
}

class FirstScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xff4f44e0),
        title: Text('Mixpanel Demo'),
      ),
      body: Center(
          child: Column(
        children: [
          SizedBox(
            height: 40,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'EVENT',
              onPressed: () {
                Navigator.pushNamed(context, '/event');
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'PROFILE',
              onPressed: () {
                Navigator.pushNamed(context, '/profile');
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'GDPR',
              onPressed: () {
                Navigator.pushNamed(context, '/gdpr');
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'GROUP',
              onPressed: () {
                Navigator.pushNamed(context, '/group');
              },
            ),
          ),
        ],
      )),
    );
  }
}

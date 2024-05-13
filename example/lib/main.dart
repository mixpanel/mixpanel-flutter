import 'event.dart';
import 'gdpr.dart';
import 'group.dart';
import 'profile.dart';
import 'package:flutter/material.dart';
import 'package:mixpanel_flutter_example/widget.dart';

// This is the main page only, check out the example app in https://github.com/mixpanel/mixpanel-flutter/tree/main/example
void main() {
  runApp(const MixPanelMain());
}

class MixPanelMain extends StatelessWidget {
  const MixPanelMain({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        initialRoute: '/',
        routes: {
          '/': (context) => FirstScreen(),
          '/event': (context) => EventScreen(),
          '/profile': (context) => ProfileScreen(),
          '/gdpr': (context) => GDPRScreen(),
          '/group': (context) => GroupScreen(),
        },
      );
}

class FirstScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final defaultWidth = width * 0.65;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xff4f44e0),
        title: const Text('Mixpanel Demo'),
      ),
      body: Center(
          child: Column(
        children: [
          const SizedBox(height: 40),
          SizedBox(
            width: defaultWidth,
            child: MixpanelButton(
              text: 'EVENT',
              onPressed: () {
                Navigator.pushNamed(context, '/event');
              },
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: defaultWidth,
            child: MixpanelButton(
              text: 'PROFILE',
              onPressed: () {
                Navigator.pushNamed(context, '/profile');
              },
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: defaultWidth,
            child: MixpanelButton(
              text: 'GDPR',
              onPressed: () {
                Navigator.pushNamed(context, '/gdpr');
              },
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: defaultWidth,
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

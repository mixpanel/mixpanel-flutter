import 'package:flutter/material.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:mixpanel_flutter_example/widget.dart';

import 'analytics.dart';
import 'event.dart';
import 'event_bridge.dart';
import 'feature_flags.dart';
import 'gdpr.dart';
import 'group.dart';
import 'profile.dart';

// This is the main page only, check out the example app in https://github.com/mixpanel/mixpanel-flutter/tree/main/example
void main() {
  runApp(MyApp());
}

class MixpanelNavigatorObserver extends NavigatorObserver {
  final Future<Mixpanel> _mixpanelFuture;

  MixpanelNavigatorObserver(this._mixpanelFuture);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    final previousName = previousRoute?.settings.name;
    final newName = route.settings.name;

    _mixpanelFuture.then((mixpanel) {
      if (previousName != null) {
        mixpanel.autocapture.trackScreenLeave(previousName);
      }
      if (newName != null) {
        mixpanel.autocapture.trackScreenView(newName);
      }
    });
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    final poppedName = route.settings.name;
    final returnToName = previousRoute?.settings.name;

    _mixpanelFuture.then((mixpanel) {
      if (poppedName != null) {
        mixpanel.autocapture.trackScreenLeave(poppedName);
      }
      if (returnToName != null) {
        mixpanel.autocapture.trackScreenView(returnToName);
      }
    });
  }
}

class MyApp extends StatefulWidget {
  const MyApp();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final Future<Mixpanel> _mixpanelFuture;
  late final MixpanelNavigatorObserver _navigatorObserver;

  @override
  void initState() {
    super.initState();
    _mixpanelFuture = MixpanelManager.init();
    _navigatorObserver = MixpanelNavigatorObserver(_mixpanelFuture);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      navigatorObservers: [_navigatorObserver],
      routes: {
        '/': (context) => FirstScreen(),
        '/event': (context) => EventScreen(),
        '/profile': (context) => ProfileScreen(),
        '/gdpr': (context) => GDPRScreen(),
        '/group': (context) => GroupScreen(),
        '/feature_flags': (context) => FeatureFlagsScreen(),
        '/event_bridge': (context) => EventBridgeScreen(),
      },
    );
  }
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
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'FEATURE FLAGS',
              onPressed: () {
                Navigator.pushNamed(context, '/feature_flags');
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'EVENT BRIDGE',
              onPressed: () {
                Navigator.pushNamed(context, '/event_bridge');
              },
            ),
          ),
        ],
      )),
    );
  }
}

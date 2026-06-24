import 'package:flutter/material.dart';
import 'package:mixpanel_flutter_example/widget.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';

import 'analytics.dart';
import 'event.dart';
import 'event_bridge.dart';
import 'feature_flags.dart';
import 'gdpr.dart';
import 'group.dart';
import 'profile.dart';

// Custom NavigatorObserver for automatic screen tracking
class MixpanelNavigatorObserver extends NavigatorObserver {
  String? _previousRouteName;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _trackScreenChange(route.settings.name);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _trackScreenChange(previousRoute?.settings.name);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _trackScreenChange(newRoute?.settings.name);
  }

  void _trackScreenChange(String? routeName) async {
    if (routeName == null || routeName.isEmpty) {
      return;
    }

    try {
      final mixpanel = await MixpanelManager.init();

      // Track screen leave for previous screen
      if (_previousRouteName != null && _previousRouteName!.isNotEmpty) {
        mixpanel.trackScreenLeave(_previousRouteName!);
      }

      // Track screen view for current screen
      mixpanel.trackScreenView(routeName);

      // Update previous route name
      _previousRouteName = routeName;
    } catch (e) {
      print('Error tracking screen change: $e');
    }
  }
}

// This is the main page only, check out the example app in https://github.com/mixpanel/mixpanel-flutter/tree/main/example
void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final MixpanelNavigatorObserver _mixpanelObserver = MixpanelNavigatorObserver();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorObservers: [_mixpanelObserver],
      initialRoute: '/',
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

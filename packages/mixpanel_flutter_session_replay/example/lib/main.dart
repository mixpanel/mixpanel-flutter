import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';
import 'package:provider/provider.dart';

import 'models/log_model.dart';
import 'screens/config_screen.dart';
import 'screens/home_screen.dart';
import 'screens/test_screens/animations_screen.dart';
import 'screens/test_screens/event_triggers_screen.dart';
import 'screens/test_screens/image_gallery_screen.dart';
import 'screens/test_screens/mixed_content_screen.dart';
import 'screens/test_screens/platform_widgets_screen.dart';
import 'screens/test_screens/rapid_scroll_screen.dart';
import 'screens/test_screens/security_test_screen.dart';
import 'screens/test_screens/text_input_screen.dart';
import 'screens/test_screens/visibility_screen.dart';
import 'utils/constants.dart';
import 'models/config_model.dart';

/// Manages the SDK instance with change notification
class MixpanelModel extends ChangeNotifier {
  MixpanelSessionReplay? _sdk;

  MixpanelSessionReplay? get sdk => _sdk;

  void setSdk(MixpanelSessionReplay? instance) {
    _sdk = instance;
    notifyListeners();
  }
}

void main() {
  // Set up logging before runApp to capture all SDK logs
  hierarchicalLoggingEnabled = true;
  Logger.root.level = Level.ALL;

  // Start capturing logs immediately
  startGlobalLogCapture();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Navigator key to preserve navigation state across rebuilds
  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MixpanelModel()),
        ChangeNotifierProvider(create: (_) => LogModel()),
        ChangeNotifierProvider(create: (_) => ConfigModel()),
      ],
      child: Consumer<MixpanelModel>(
        builder: (context, mixpanelModel, child) {
          return MixpanelSessionReplayWidget(
            instance: mixpanelModel.sdk,
            child: MaterialApp(
              navigatorKey: navigatorKey,
              title: 'Session Replay Test Platform',
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
              ),
              initialRoute: AppRoutes.config,
              onGenerateRoute: _buildRoute,
            ),
          );
        },
      ),
    );
  }

  Route? _buildRoute(RouteSettings settings) {
    // Get context from navigator key to access Provider
    final context = navigatorKey.currentContext;
    if (context == null) return null;

    final routes = <String, WidgetBuilder>{
      AppRoutes.config: (_) =>
          ConfigScreen(onSdkInitialized: context.read<MixpanelModel>().setSdk),
      AppRoutes.home: (_) => const HomeScreen(),
      AppRoutes.mixedContent: (_) => const MixedContentScreen(),
      AppRoutes.animations: (_) => const AnimationsScreen(),
      AppRoutes.visibility: (_) => const VisibilityScreen(),
      AppRoutes.textInput: (_) => const TextInputScreen(),
      AppRoutes.imageGallery: (_) => const ImageGalleryScreen(),
      AppRoutes.rapidScroll: (_) => const RapidScrollScreen(),
      AppRoutes.platformWidgets: (_) => const PlatformWidgetsScreen(),
      AppRoutes.security: (_) => const SecurityTestScreen(),
      AppRoutes.eventTriggers: (_) => const EventTriggersScreen(),
    };

    final builder = routes[settings.name];
    if (builder == null) return null;

    return MaterialPageRoute(builder: builder, settings: settings);
  }
}

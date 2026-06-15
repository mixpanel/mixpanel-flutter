import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../services/mixpanel_analytics.dart';
import '../widgets/logs_bottom_sheet.dart';
import 'dashboard_tab.dart';
import 'settings_tab.dart';

const _tabNames = ['Tests', 'Settings'];

/// Home screen with tabbed navigation
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final sdk = context.watch<MixpanelModel>().sdk;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Replay Test Platform'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Flush button
          IconButton(
            icon: const Icon(Icons.upload),
            tooltip: 'Flush Events',
            onPressed: () async {
              await sdk?.flush();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Flushing events...'),
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
          ),
          // Logs button
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'View Logs',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (modalContext) => const LogsBottomSheet(),
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [const DashboardTab(), const SettingsTab()],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          MixpanelAnalytics.instance?.track(
            'Tab Clicked',
            properties: {'tab_name': _tabNames[index]},
          );
          setState(() => _currentIndex = index);
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Tests'),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:mixpanel_flutter_common/mixpanel_flutter_common.dart';
import 'package:mixpanel_flutter_example/widget.dart';

import 'analytics.dart';

/// Manual test harness for the MixpanelEventBridge.
///
/// Supports any number of independent listeners. Use in combination with
/// the native platform logs (`Mixpanel/EventBridge` tag) to verify that:
///   - The native bridge stays idle until the first subscriber attaches.
///   - Every active listener sees every event (broadcast fan-out).
///   - The native bridge tears down only when the LAST listener cancels.
///   - Tracking events with zero listeners does not forward through the
///     bridge.
class EventBridgeScreen extends StatefulWidget {
  const EventBridgeScreen({Key? key}) : super(key: key);

  @override
  State<EventBridgeScreen> createState() => _EventBridgeScreenState();
}

class _EventBridgeScreenState extends State<EventBridgeScreen> {
  late final Mixpanel _mixpanel;
  final List<_Listener> _listeners = [];
  int _nextId = 1;

  @override
  void initState() {
    super.initState();
    _initMixpanel();
  }

  Future<void> _initMixpanel() async {
    _mixpanel = await MixpanelManager.init();
  }

  @override
  void dispose() {
    for (final l in _listeners) {
      l.subscription.cancel();
    }
    super.dispose();
  }

  void _addListener() {
    final id = _nextId++;
    late final _Listener listener;
    final subscription = MixpanelEventBridge.events.listen((event) {
      setState(() {
        listener.count++;
        listener.lastEvent = event.eventName;
      });
    });
    listener = _Listener(id: id, subscription: subscription);
    setState(() => _listeners.add(listener));
  }

  void _cancelListener(_Listener listener) {
    listener.subscription.cancel();
    setState(() => _listeners.remove(listener));
  }

  void _cancelAll() {
    for (final l in _listeners) {
      l.subscription.cancel();
    }
    setState(() => _listeners.clear());
  }

  void _track() {
    _mixpanel.track('Bridge Test Event', properties: {
      'source': 'EventBridgeScreen',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = _listeners.length;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xff4f44e0),
        title: const Text('Event Bridge'),
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              count == 0
                  ? 'No listeners — native bridge should be idle.'
                  : '$count listener${count == 1 ? '' : 's'} active — native bridge running.',
              style: TextStyle(
                fontSize: 14,
                color: count == 0 ? Colors.grey[700] : Colors.green[700],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Add Listener',
              onPressed: _addListener,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Track Test Event',
              onPressed: _track,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Cancel All Listeners',
              onPressed: count == 0 ? () {} : _cancelAll,
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: _listeners.isEmpty
                ? const Center(
                    child: Text(
                      'No active listeners.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _listeners.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final l = _listeners[i];
                      return ListTile(
                        dense: true,
                        title: Text('Listener #${l.id}'),
                        subtitle: Text(
                          '${l.count} event${l.count == 1 ? '' : 's'}'
                          '${l.lastEvent == null ? '' : ' • last: ${l.lastEvent}'}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Cancel this listener',
                          onPressed: () => _cancelListener(l),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Listener {
  _Listener({required this.id, required this.subscription});

  final int id;
  final StreamSubscription<MixpanelEvent> subscription;
  int count = 0;
  String? lastEvent;
}

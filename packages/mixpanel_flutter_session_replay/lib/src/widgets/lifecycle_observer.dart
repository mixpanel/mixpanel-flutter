import 'package:flutter/widgets.dart';

import '../internal/widget_coordinator.dart';

/// Observes app lifecycle state changes and flushes queued events when the app
/// is backgrounded or minimized.
///
/// This widget monitors [AppLifecycleState.hidden] which is triggered when:
/// - Mobile (iOS/Android): App is backgrounded
/// - Desktop (macOS/Windows/Linux): Windows are minimized or hidden
/// - Web: Browser tab is backgrounded
///
/// When the app enters the hidden state, all queued session replay events are
/// immediately flushed to ensure data isn't lost.
class LifecycleObserver extends StatefulWidget {
  const LifecycleObserver({
    super.key,
    required this.coordinator,
    required this.child,
  });

  /// The session replay coordinator that manages event flushing
  final WidgetCoordinator coordinator;

  /// The child widget to wrap
  final Widget child;

  @override
  State<LifecycleObserver> createState() => _LifecycleObserverState();
}

class _LifecycleObserverState extends State<LifecycleObserver>
    with WidgetsBindingObserver {
  AppLifecycleState? _lastState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Check initial lifecycle state and start uploads if resumed
    final initialState = WidgetsBinding.instance.lifecycleState;
    if (initialState == AppLifecycleState.resumed) {
      widget.coordinator.logger.info(
        'LifecycleObserver detected initial resume state',
      );
      widget.coordinator.onAppForegrounded();
    }
    _lastState = initialState;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _handleLifecycleTransition(state);
  }

  /// Handle lifecycle state transitions and trigger appropriate actions
  void _handleLifecycleTransition(AppLifecycleState state) {
    widget.coordinator.logger.debug(
      'LifecycleObserver detected state change: $_lastState → $state',
    );

    // Get visibility levels for comparison
    final currentLevel = _getVisibilityLevel(state);
    final lastLevel = _lastState != null
        ? _getVisibilityLevel(_lastState!)
        : null;

    // Detect transition to inactive
    // Only trigger if coming from a MORE visible state (resumed)
    if (state == AppLifecycleState.inactive &&
        lastLevel != null &&
        lastLevel > currentLevel) {
      widget.coordinator.logger.info(
        'LifecycleObserver detected app becoming inactive',
      );
      widget.coordinator.onAppBackgrounded();
    }

    // Detect transition to resumed
    // Trigger if: no previous state OR coming from a LESS visible state
    if (state == AppLifecycleState.resumed &&
        (lastLevel == null || lastLevel < currentLevel)) {
      widget.coordinator.logger.info('LifecycleObserver detected app resuming');
      widget.coordinator.onAppForegrounded();
    }

    _lastState = state;
  }

  @override
  Widget build(BuildContext context) => widget.child;

  /// Assign visibility levels to lifecycle states
  /// Higher values = more visible/active
  /// resumed (3) > inactive (2) > hidden (1) > paused (0) > detached (-1)
  int _getVisibilityLevel(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        return 3; // Fully visible and interactive
      case AppLifecycleState.inactive:
        return 2; // Visible but not interactive (e.g., notification shade pulled down)
      case AppLifecycleState.hidden:
        return 1; // Not visible but app still running
      case AppLifecycleState.paused:
        return 0; // Backgrounded, may be suspended
      case AppLifecycleState.detached:
        return -1; // Initial state or app being terminated
    }
  }
}

import 'package:flutter/widgets.dart';

import '../internal/widget_coordinator.dart';
import '../internal/platform/web_page_lifecycle.dart';

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
  void Function()? _disposeWebPageLifecycle;
  bool _isInForeground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Enter the foreground if the app is already there when mounted. On web
    // that includes a visible page whose window has lost focus, since the SDK
    // may finish initializing while focus is in the address bar or devtools.
    final initialState = WidgetsBinding.instance.lifecycleState;
    if (initialState != null && _isForegroundState(initialState)) {
      widget.coordinator.logger.info(
        'LifecycleObserver detected initial foreground state: $initialState',
      );
      _enterForeground();
    }
    _lastState = initialState;
    // Flutter normally maps document visibility into AppLifecycleState, but a
    // pagehide (notably a back-forward-cache transition) is a separate browser
    // signal. Mixpanel JS listens to both, so replay does too. The shared gate
    // prevents duplicate callbacks when both signals describe one transition.
    _disposeWebPageLifecycle = registerWebPageLifecycle(
      onHidden: _leaveForeground,
      onVisible: _enterForeground,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeWebPageLifecycle?.call();
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

    // Detect crossing the foreground threshold in either direction. Mobile
    // commonly passes resumed -> inactive -> hidden, and inactive is where it
    // leaves. Web leaves only when the page is hidden, which may come straight
    // from resumed or after a blur (inactive). Crossing the threshold, rather
    // than any drop, produces exactly one callback for each shape.
    final wasInForeground =
        _lastState != null && _isForegroundState(_lastState!);
    final isInForeground = _isForegroundState(state);
    if (wasInForeground && !isInForeground) {
      widget.coordinator.logger.info(
        'LifecycleObserver detected app leaving the foreground',
      );
      _leaveForeground();
    } else if (!wasInForeground && isInForeground) {
      widget.coordinator.logger.info(
        'LifecycleObserver detected app entering the foreground',
      );
      _enterForeground();
    }

    _lastState = state;
  }

  /// Whether [state] is above the coordinator's background threshold. Native
  /// counts only resumed as foreground; web also counts inactive, a visible
  /// page whose window lost focus.
  bool _isForegroundState(AppLifecycleState state) =>
      _getVisibilityLevel(state) >
      _getVisibilityLevel(
        widget.coordinator.leavesForegroundWhenInactive
            ? AppLifecycleState.inactive
            : AppLifecycleState.hidden,
      );

  void _leaveForeground() {
    if (!_isInForeground) return;
    _isInForeground = false;
    widget.coordinator.onAppBackgrounded();
  }

  void _enterForeground() {
    if (_isInForeground) return;
    _isInForeground = true;
    widget.coordinator.onAppForegrounded();
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

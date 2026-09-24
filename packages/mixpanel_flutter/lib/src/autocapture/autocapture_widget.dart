part of '../../mixpanel_flutter.dart';

/// Observes pointer clicks within [child] on Android and iOS.
///
/// Place once above MaterialApp/CupertinoApp and its navigators.
/// [instance] may be null while initialization completes. The child is not
/// remounted when capture is enabled/disabled. Requires opt-in options at init.
/// Register [MixpanelAutocaptureNavigatorObserver] for every navigator as well.
///
/// Does not observe keyboard/assistive activation or content inside platform
/// views. Unknown response coverage suppresses automatic dead clicks; use the
/// manual APIs for app-detected signals on unsupported surfaces.
///
/// **Experimental (beta).** Autocapture may contain issues, and its API and the
/// properties it captures may change in a future release before general
/// availability. Pin your SDK version if you build reports on autocaptured events.
class MixpanelAutocaptureWidget extends StatefulWidget {
  const MixpanelAutocaptureWidget(
      {super.key, required this.instance, required this.child});
  final Mixpanel? instance;
  final Widget child;
  @override
  State<MixpanelAutocaptureWidget> createState() => _CaptureState();
}

class _CaptureState extends State<MixpanelAutocaptureWidget>
    with WidgetsBindingObserver {
  final _resolver = TargetResolver();
  final _taps = PointerTapTracker();
  AutocaptureController? _controller;
  RageClickTracker? _rage;
  late final DeadClickDetector _dead = DeadClickDetector(
    capture: _snapshot,
  );
  late final _responses = UiResponseTracker(
      capture: _snapshot,
      canObserve: () => _allowed,
      hasCandidate: () => _dead.observing,
      onSnapshot: _dead.sampleSnapshot,
      onResponse: _dead.cancel);
  int? _viewId;
  bool _ownsView = false;
  bool _monitoring = false;
  bool _foreground = true;
  _PendingTap? _pendingTap;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool get _allowed =>
      _supported && _foreground && _ownsView && (_controller?.allowed ?? false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = View.of(context).viewId;
    if (_viewId != id) {
      _detach();
      _viewId = id;
    }
    _attach();
  }

  @override
  void didUpdateWidget(MixpanelAutocaptureWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.instance, widget.instance)) {
      _detach();
      _attach();
    }
  }

  void _attach() {
    final controller = widget.instance?._autocaptureController;
    if (identical(controller, _controller)) return;
    _controller = controller;
    if (controller == null || _viewId == null) return;
    _ownsView = controller.claim(_viewId!, this);
    _rage = RageClickTracker(controller.options.rageClickOptions);
    controller.addListener(_sync);
    _sync();
  }

  void _sync() {
    _reset();
    final observe = _supported && _ownsView && (_controller?.allowed ?? false);
    if (observe) {
      _startMonitoring();
    } else {
      _stopMonitoring();
    }
  }

  void _startMonitoring() {
    if (_monitoring) return;
    _monitoring = true;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _responses.start();
  }

  void _stopMonitoring() {
    if (!_monitoring) return;
    _monitoring = false;
    WidgetsBinding.instance.removeObserver(this);
    _responses.stop();
  }

  void _detach() {
    _reset();
    _stopMonitoring();
    _controller?.removeListener(_sync);
    if (_viewId != null) _controller?.release(_viewId!, this);
    _controller = null;
    _ownsView = false;
  }

  void _reset() {
    _taps.reset();
    _clearPress();
    _dead.cancel();
    _rage?.reset();
  }

  void _clearPress() {
    _pendingTap = null;
    _responses.cancelPress();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _reset();
  }

  ResponseSnapshot? _snapshot() {
    if (!mounted || !_allowed) {
      return null;
    }
    final view = View.of(context);
    return ResponseSnapshot.capture(context as Element,
        Offset.zero & (view.physicalSize / view.devicePixelRatio));
  }

  void _down(PointerDownEvent event) {
    if (!_allowed || event.viewId != _viewId) return;
    final slop = computeHitSlop(
        event.kind, MediaQuery.maybeOf(context)?.gestureSettings);
    if (!_taps.down(event, slop)) {
      if (!_taps.hasPress) _clearPress();
      return;
    }
    final controller = _controller;
    if (controller == null) return;
    try {
      final target = _resolver.resolve(context as Element, event);
      if (target == null) {
        _clearPress();
        return;
      }
      // Capture before ordinary tap handlers; raw pointer handlers may run earlier.
      _pendingTap = _PendingTap(target, controller.session);
      if (controller.options.deadClickOptions.enabled && target.deadEligible) {
        _responses.beginPress();
      }
    } catch (_) {
      _clearPress();
    }
  }

  void _move(PointerMoveEvent event) {
    _taps.move(event);
    if (!_taps.hasPress) _clearPress();
  }

  void _cancel(PointerCancelEvent event) {
    _taps.cancel(event);
    _clearPress();
  }

  void _up(PointerUpEvent event) {
    final accepted = _taps.up(event);
    final tap = _pendingTap;
    final baseline = _responses.takeBaseline();
    _clearPress();
    final controller = _controller;
    final rage = _rage;
    if (!accepted ||
        tap == null ||
        !tap.target.element.mounted ||
        !_allowed ||
        controller == null ||
        rage == null ||
        !tap.session.isActive) {
      return;
    }
    final target = tap.target;
    final session = tap.session;
    final old = target.event;
    final click = ClickEvent(
        x: event.position.dx,
        y: event.position.dy,
        elementId: old.elementId,
        tagName: old.tagName,
        role: old.role,
        elements: old.elements);
    final options = controller.options;
    // Android parity: even an ineligible new tap cancels the previous check.
    _dead.cancel();
    if (options.clickOptions.enabled) {
      controller.emit(r'$mp_click', click, session);
    }
    if (options.rageClickOptions.enabled &&
        rage.record(click.x, click.y, event.timeStamp)) {
      controller.emit(r'$mp_rage_click', click, session);
    }
    if (options.deadClickOptions.enabled &&
        target.deadEligible &&
        baseline != null) {
      final targetReference = WeakReference(target.element);
      _dead.start(
          baseline: baseline,
          event: click,
          timeout: options.deadClickOptions.timeWindow,
          isValid: () =>
              session.isActive && (targetReference.target?.mounted ?? false),
          onDetected: (event) =>
              controller.emit(r'$mp_dead_click', event, session));
    }
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _responses.onScroll,
        child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _cancel,
            child: widget.child),
      );

  @override
  void dispose() {
    _detach();
    super.dispose();
  }
}

/// State belonging to one press; cancellation drops it as a unit.
class _PendingTap {
  _PendingTap(this.target, this.session);
  final CaptureTarget target;
  final DetectionSession session;
}

/// Cancels pending signals on navigation without collecting route metadata.
/// Register a separate observer on each root/nested Navigator. Router-based apps
/// should attach it to their Navigator's observers list.
///
/// **Experimental (beta).** Autocapture may contain issues, and its API and the
/// properties it captures may change in a future release before general
/// availability. Pin your SDK version if you build reports on autocaptured events.
class MixpanelAutocaptureNavigatorObserver extends NavigatorObserver {
  MixpanelAutocaptureNavigatorObserver({required this.instance});
  final Mixpanel instance;
  void _change() => instance._autocaptureController?.invalidate();
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _change();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _change();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _change();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _change();
}

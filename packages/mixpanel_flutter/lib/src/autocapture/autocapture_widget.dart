part of '../../mixpanel_flutter.dart';

/// Observes pointer clicks within [child] on Android and iOS.
///
/// Place once above MaterialApp/CupertinoApp and its navigators.
/// [instance] may be null while initialization completes. The child is not
/// remounted when capture is enabled/disabled. Requires opt-in options at init.
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
  late final _dead = DeadClickDetector(capture: _snapshot);
  RageClickTracker? _rage;
  // An outer capture widget already observes this subtree.
  late final bool _nested =
      context.findAncestorStateOfType<_CaptureState>() != null;
  CaptureTarget? _pendingTap;
  ResponseSnapshot? _baseline;

  AutocaptureOptions? get _options => !_nested &&
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)
      ? widget.instance?._autocaptureOptions
      : null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_onResponse);
  }

  @override
  void didUpdateWidget(MixpanelAutocaptureWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.instance, widget.instance)) {
      _reset();
      _rage = null;
    }
  }

  @override
  void dispose() {
    _reset();
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_onResponse);
    super.dispose();
  }

  void _reset() {
    _taps.reset();
    _clearPress();
    _dead.cancel();
    _rage?.reset();
  }

  void _clearPress() {
    _pendingTap = null;
    _baseline = null;
  }

  /// Early cancellation hints: scroll, focus and window-metrics changes.
  void _onResponse() {
    _baseline = null;
    _dead.cancel();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification ||
        notification is OverscrollNotification) {
      _onResponse();
    }
    return false;
  }

  @override
  void didChangeMetrics() => _onResponse();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _reset();

  ResponseSnapshot? _snapshot() {
    if (!mounted) return null;
    final view = View.of(context);
    return ResponseSnapshot.capture(context as Element,
        Offset.zero & (view.physicalSize / view.devicePixelRatio));
  }

  void _down(PointerDownEvent event) {
    final options = _options;
    if (options == null) return;
    _clearPress();
    final slop = computeHitSlop(
        event.kind, MediaQuery.maybeOf(context)?.gestureSettings);
    if (!_taps.down(event, slop)) return;
    final target = _resolver.resolve(context as Element, event);
    if (target == null) return;
    _pendingTap = target;
    // Capture before ordinary tap handlers; raw pointer handlers may run earlier.
    if (options.deadClickOptions.enabled && target.deadEligible) {
      _baseline = _snapshot();
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
    final target = _pendingTap;
    final baseline = _baseline;
    _clearPress();
    final options = _options;
    final instance = widget.instance;
    if (!accepted ||
        target == null ||
        options == null ||
        instance == null ||
        !target.element.mounted) {
      return;
    }
    final old = target.event;
    final click = ClickEvent(
        x: event.position.dx,
        y: event.position.dy,
        elementId: old.elementId,
        tagName: old.tagName,
        role: old.role,
        elements: old.elements);
    // _trackClickEvent contains its own errors and invokes the channel
    // synchronously, so a later identify cannot relabel this event.
    void emit(String name, ClickEvent e) =>
        unawaited(instance.autocapture._trackClickEvent(name, e, null));
    // Every accepted tap cancels the previous check, even an ineligible one.
    _dead.cancel();
    if (options.clickOptions.enabled) emit(r'$mp_click', click);
    final rage = _rage ??= RageClickTracker(options.rageClickOptions);
    if (options.rageClickOptions.enabled &&
        rage.record(click.x, click.y, event.timeStamp)) {
      emit(r'$mp_rage_click', click);
    }
    if (options.deadClickOptions.enabled &&
        target.deadEligible &&
        baseline != null) {
      _dead.start(
          baseline: baseline,
          event: click,
          timeout: options.deadClickOptions.timeWindow,
          onDetected: (e) => emit(r'$mp_dead_click', e));
    }
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _cancel,
            child: widget.child),
      );
}

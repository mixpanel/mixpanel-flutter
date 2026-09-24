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
  // Non-null only while automatic capture is enabled. When null, nothing is
  // registered and pointer events pass straight through.
  _Detectors? _detectors;
  CaptureTarget? _pendingTap;
  ResponseSnapshot? _baseline;

  @override
  void initState() {
    super.initState();
    assert(context.findAncestorStateOfType<_CaptureState>() == null,
        'Place a single MixpanelAutocaptureWidget above the app.');
    _configure();
  }

  @override
  void didUpdateWidget(MixpanelAutocaptureWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.instance, widget.instance)) _configure();
  }

  @override
  void dispose() {
    _disable();
    super.dispose();
  }

  void _configure() {
    _disable();
    final instance = widget.instance;
    final options = instance?._autocaptureOptions;
    final supported = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (instance == null || options == null || !supported) return;
    _detectors = _Detectors(instance, options, _snapshot);
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_onResponse);
  }

  void _disable() {
    final detectors = _detectors;
    if (detectors == null) return;
    _reset();
    detectors.dispose();
    _detectors = null;
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_onResponse);
  }

  void _reset() {
    _taps.reset();
    _clearPress();
    _detectors?.reset();
  }

  void _clearPress() {
    _pendingTap = null;
    _baseline = null;
  }

  /// Early cancellation hints: scroll, focus and window-metrics changes.
  void _onResponse() {
    _baseline = null;
    _detectors?.dead.cancel();
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
    final detectors = _detectors;
    if (detectors == null) return;
    _clearPress();
    final slop = computeHitSlop(
        event.kind, MediaQuery.maybeOf(context)?.gestureSettings);
    if (!_taps.down(event, slop)) return;
    final target = _resolver.resolve(context as Element, event);
    if (target == null) return;
    _pendingTap = target;
    // Capture before ordinary tap handlers; raw pointer handlers may run earlier.
    _baseline = detectors.dead.baselineFor(target);
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
    final detectors = _detectors;
    if (!accepted ||
        target == null ||
        detectors == null ||
        !target.element.mounted) {
      return;
    }
    final old = target.event;
    detectors.onTap(
        ClickEvent(
            x: event.position.dx,
            y: event.position.dy,
            elementId: old.elementId,
            tagName: old.tagName,
            role: old.role,
            elements: old.elements),
        event.timeStamp,
        baseline);
  }

  // The tree shape never changes, so enabling capture after asynchronous
  // initialization does not remount [child]; only the callbacks are toggled.
  @override
  Widget build(BuildContext context) {
    final enabled = _detectors != null;
    return NotificationListener<ScrollNotification>(
      onNotification: enabled ? _onScroll : null,
      child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: enabled ? _down : null,
          onPointerMove: enabled ? _move : null,
          onPointerUp: enabled ? _up : null,
          onPointerCancel: enabled ? _cancel : null,
          child: widget.child),
    );
  }
}

/// Detectors for one enabled instance; each detector applies its own options.
class _Detectors {
  _Detectors(Mixpanel instance, AutocaptureOptions options,
      ResponseSnapshot? Function() capture)
      : _autocapture = instance.autocapture,
        _clickEnabled = options.clickOptions.enabled,
        rage = RageClickTracker(options.rageClickOptions),
        dead = DeadClickDetector(options.deadClickOptions, capture: capture);
  final Autocapture _autocapture;
  final bool _clickEnabled;
  final RageClickTracker rage;
  final DeadClickDetector dead;

  // _trackClickEvent contains its own errors and invokes the channel
  // synchronously, so a later identify cannot relabel this event.
  void _emit(String name, ClickEvent event) =>
      unawaited(_autocapture._trackClickEvent(name, event, null));

  void onTap(ClickEvent click, Duration time, ResponseSnapshot? baseline) {
    if (_clickEnabled) _emit(r'$mp_click', click);
    if (rage.record(click.x, click.y, time)) _emit(r'$mp_rage_click', click);
    dead.start(baseline, click, (e) => _emit(r'$mp_dead_click', e));
    // identify() and reset() cancel a check that is still pending.
    Mixpanel._cancelPendingAutocapture = dead.cancel;
  }

  void reset() {
    dead.cancel();
    rage.reset();
  }

  void dispose() {
    if (Mixpanel._cancelPendingAutocapture == dead.cancel) {
      Mixpanel._cancelPendingAutocapture = null;
    }
  }
}

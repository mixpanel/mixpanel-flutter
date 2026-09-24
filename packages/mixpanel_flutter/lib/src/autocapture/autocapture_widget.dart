part of '../../mixpanel_flutter.dart';

/// Observes pointer clicks within [child] on Android, iOS and web.
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
  // Non-null only while automatic capture is enabled. When null, nothing is
  // registered and pointer events pass straight through.
  CaptureSession? _session;

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
    // Desktop is not yet validated.
    final supported = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (instance == null || options == null || !supported) return;
    final autocapture = instance.autocapture;
    final session = CaptureSession(options,
        root: context as Element,
        capture: _snapshot,
        // _trackClickEvent contains its own errors and invokes the channel
        // synchronously.
        emit: (name, event) =>
            unawaited(autocapture._trackClickEvent(name, event, null)));
    _session = session;
    Mixpanel._cancelPendingAutocapture = session.cancelPendingCheck;
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_onResponse);
  }

  void _disable() {
    final session = _session;
    if (session == null) return;
    session.reset();
    if (Mixpanel._cancelPendingAutocapture == session.cancelPendingCheck) {
      Mixpanel._cancelPendingAutocapture = null;
    }
    _session = null;
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_onResponse);
  }

  /// Early cancellation hints: scroll, focus and window-metrics changes.
  void _onResponse() => _session?.onResponse();

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
  void didChangeAppLifecycleState(AppLifecycleState state) => _session?.reset();

  ResponseSnapshot? _snapshot() {
    if (!mounted) return null;
    final view = View.of(context);
    return ResponseSnapshot.capture(context as Element,
        Offset.zero & (view.physicalSize / view.devicePixelRatio));
  }

  void _down(PointerDownEvent event) => _session?.down(event,
      computeHitSlop(event.kind, MediaQuery.maybeOf(context)?.gestureSettings));
  void _move(PointerMoveEvent event) => _session?.move(event);
  void _cancel(PointerCancelEvent event) => _session?.cancel(event);
  void _up(PointerUpEvent event) => _session?.up(event);

  // The tree shape never changes, so enabling capture after asynchronous
  // initialization does not remount [child]; only the callbacks are toggled.
  @override
  Widget build(BuildContext context) {
    final enabled = _session != null;
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

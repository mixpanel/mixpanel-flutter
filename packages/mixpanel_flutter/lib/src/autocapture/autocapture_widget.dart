import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import '../../mixpanel_flutter.dart';
import 'autocapture_controller.dart';
import 'autocapture_binding.dart';
import 'dead_click_detector.dart';
import 'rage_click_tracker.dart';
import 'response_snapshot.dart';
import 'target_resolver.dart';

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
  // Accept taps lasting at most 500 ms (inclusive).
  static const _maxTapDuration = Duration(milliseconds: 500);
  final _resolver = TargetResolver();
  final _pointers = <int>{};
  AutocaptureController? _controller;
  RageClickTracker? _rage;
  late final DeadClickDetector _dead = DeadClickDetector(
    capture: _snapshot,
  );
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
    final controller = AutocaptureBinding.getController(widget.instance);
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
    if (observe == _monitoring) return;
    _monitoring = observe;
    if (observe) {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
      WidgetsBinding.instance.addObserver(this);
      FocusManager.instance.addListener(_response);
      CaptureFrameObserver.add(_frame, _isObserving);
    } else {
      WidgetsBinding.instance.removeObserver(this);
      FocusManager.instance.removeListener(_response);
      CaptureFrameObserver.remove(_frame);
    }
  }

  void _detach() {
    _reset();
    if (_monitoring) {
      WidgetsBinding.instance.removeObserver(this);
      FocusManager.instance.removeListener(_response);
      CaptureFrameObserver.remove(_frame);
      _monitoring = false;
    }
    _controller?.removeListener(_sync);
    if (_viewId != null) _controller?.release(_viewId!, this);
    _controller = null;
    _ownsView = false;
  }

  void _reset() {
    _pointers.clear();
    _clearPress();
    _dead.cancel();
    _rage?.reset();
  }

  void _clearPress() => _pendingTap = null;

  void _response() {
    _pendingTap?.baseline = null;
    _dead.cancel();
  }

  @override
  void didChangeMetrics() => _response();
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

  bool _isObserving() =>
      _allowed && (_dead.observing || _pendingTap?.baseline != null);

  void _frame() {
    if (!_isObserving()) return;
    final current = _snapshot();
    _dead.sampleSnapshot(current);
    final baseline = _pendingTap?.baseline;
    if (baseline != null &&
        (current == null || baseline.differsFrom(current))) {
      _pendingTap?.baseline = null;
    }
  }

  void _down(PointerDownEvent event) {
    if (!_allowed || event.viewId != _viewId) return;
    if (event.kind != PointerDeviceKind.touch &&
        event.kind != PointerDeviceKind.mouse) {
      return;
    }
    _pointers.add(event.pointer);
    if (_pointers.length != 1) {
      _clearPress();
      return;
    }
    if (event.buttons != kPrimaryButton) {
      _clearPress();
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
      final slop = computeHitSlop(
          event.kind, MediaQuery.maybeOf(context)?.gestureSettings);
      // Normal tap handlers run after this baseline. Custom raw pointer handlers
      // can run earlier, so their response coverage is intentionally unsupported.
      _pendingTap = _PendingTap(
          target: target,
          origin: event.position,
          downTime: event.timeStamp,
          session: controller.session,
          slopSquared: slop * slop,
          baseline:
              controller.options.deadClickOptions.enabled && target.deadEligible
                  ? _snapshot()
                  : null);
    } catch (_) {
      _clearPress();
    }
  }

  void _move(PointerMoveEvent event) {
    final tap = _pendingTap;
    if (tap == null || !_pointers.contains(event.pointer)) return;
    if ((event.position - tap.origin).distanceSquared > tap.slopSquared) {
      tap.moved = true;
      tap.baseline = null;
    }
  }

  void _cancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    _clearPress();
  }

  void _up(PointerUpEvent event) {
    final wasSingle =
        _pointers.length == 1 && _pointers.contains(event.pointer);
    _pointers.remove(event.pointer);
    final tap = _pendingTap;
    _clearPress();
    final controller = _controller;
    final rage = _rage;
    if (!wasSingle ||
        tap == null ||
        !tap.accepts(event, _maxTapDuration) ||
        !_allowed ||
        controller == null ||
        rage == null ||
        !tap.session.isActive) {
      return;
    }
    final target = tap.target;
    final baseline = tap.baseline;
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
      _dead.begin(baseline);
      _dead.arm(click, options.deadClickOptions.timeWindow,
          isValid: () =>
              session.isActive && (targetReference.target?.mounted ?? false),
          onDetected: (event) =>
              controller.emit(r'$mp_dead_click', event, session));
    }
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification ||
              notification is OverscrollNotification) {
            _response();
          }
          return false;
        },
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
  _PendingTap(
      {required this.target,
      required this.origin,
      required this.downTime,
      required this.session,
      required this.slopSquared,
      this.baseline});
  final CaptureTarget target;
  final Offset origin;
  final Duration downTime;
  final CaptureSession session;
  final double slopSquared;
  ResponseSnapshot? baseline;
  bool moved = false;

  bool accepts(PointerUpEvent event, Duration maxDuration) =>
      !moved &&
      target.element.mounted &&
      event.timeStamp >= downTime &&
      event.timeStamp - downTime <= maxDuration &&
      (event.position - origin).distanceSquared <= slopSquared;
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
  void _change() => AutocaptureBinding.getController(instance)?.invalidate();
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

import 'dart:async';

import 'package:meta/meta.dart';

import 'mixpanel_event.dart';

/// Process-wide bridge for tracked Mixpanel events.
///
/// Direct Dart analog of the native dispatchers:
/// - Android `MixpanelEventBridge` (Kotlin SharedFlow)
/// - Swift `MixpanelEventBridge.shared.eventStream()` (AsyncStream)
///
/// `mixpanel_flutter`'s native plugins subscribe to their platform's native
/// bridge and forward each event into [notifyListeners]. Any number of
/// Dart consumers (session replay, custom triggers) subscribe to [events].
///
/// ## Lazy wiring
/// `mixpanel_flutter` registers a one-shot wiring hook via
/// [setSourceWiringHook] during `init()`. The hook fires the first time
/// anything reads [events] and installs the MethodChannel handler plus
/// lifecycle callbacks. Apps that never consume events pay only for one
/// stored function reference — no handler is installed and no native
/// subscription is ever started.
///
/// ## Lazy native subscription
/// Once the source is wired, the native bridge subscription itself is
/// only activated while at least one Dart listener is attached. The first
/// listener triggers `onActivate` (which starts the native subscription),
/// and the last cancel triggers `onDeactivate` (which stops it).
///
/// ## Late subscribers
/// The stream does not buffer or replay. Events emitted before a listener
/// attaches are dropped. This matches the native `replay = 0` semantics.
///
/// ## Handler expectations
/// Keep listeners fast and non-blocking — there is no backpressure buffer
/// for slow consumers. A long-running handler will queue microtasks
/// unboundedly. If you need network I/O on each event, buffer the event
/// locally and process asynchronously without awaiting in the listener.
class MixpanelEventBridge {
  MixpanelEventBridge._();

  static void Function()? _onActivate;
  static void Function()? _onDeactivate;
  static void Function()? _ensureSourceWired;

  static final StreamController<MixpanelEvent> _controller =
      StreamController<MixpanelEvent>.broadcast(
        onListen: () => _onActivate?.call(),
        onCancel: () => _onDeactivate?.call(),
      );

  /// Subscribe to all events tracked by Mixpanel.
  ///
  /// Returns a broadcast [Stream]; multiple listeners are supported. Each
  /// listener sees every event from the moment it subscribes.
  ///
  /// Intended for Mixpanel-authored downstream packages.
  @internal
  static Stream<MixpanelEvent> get events {
    // Fire the wiring hook at most once. Cleared before invocation so the
    // hook can't re-enter itself via `events` from inside `mixpanel_flutter`'s
    // setup path.
    final hook = _ensureSourceWired;
    if (hook != null) {
      _ensureSourceWired = null;
      hook();
    }
    return _controller.stream;
  }

  /// Internal entry point — invoked by `mixpanel_flutter`'s plugin after
  /// the native SDK has tracked and decorated an event.
  ///
  /// Application code should never call this directly. It is left public
  /// (rather than library-private) so the `mixpanel_flutter` package can
  /// reach it without circular imports.
  @internal
  static void notifyListeners({
    required String eventName,
    Map<String, Object?>? properties,
  }) {
    _controller.add(
      MixpanelEvent(eventName: eventName, properties: properties),
    );
  }

  /// Registers hooks invoked when the listener count transitions across zero.
  ///
  /// `onActivate` fires the moment a first listener attaches to a previously
  /// empty broadcast stream; `onDeactivate` fires when the last listener
  /// cancels. `mixpanel_flutter` uses these to start/stop the native event
  /// bridge subscription lazily so the MethodChannel stays idle when no
  /// Dart consumer cares about events.
  ///
  /// Application code should never call this directly.
  @internal
  static void setLifecycleCallbacks({
    void Function()? onActivate,
    void Function()? onDeactivate,
  }) {
    _onActivate = onActivate;
    _onDeactivate = onDeactivate;
  }

  /// Registers a one-shot hook fired the first time [events] is read.
  ///
  /// `mixpanel_flutter` uses this to defer installing its MethodChannel
  /// handler (and registering [setLifecycleCallbacks]) until a Dart
  /// consumer actually asks for the stream. The hook is single-shot —
  /// once consumed it is cleared, so the registered setup runs at most
  /// once per process unless re-registered.
  ///
  /// Pass `null` (or no argument) to clear an existing hook.
  ///
  /// Application code should never call this directly.
  @internal
  static void setSourceWiringHook([void Function()? hook]) {
    _ensureSourceWired = hook;
  }
}

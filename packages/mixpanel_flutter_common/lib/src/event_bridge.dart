import 'dart:async';

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

  static final StreamController<MixpanelEvent> _controller =
      StreamController<MixpanelEvent>.broadcast();

  /// Subscribe to all events tracked by Mixpanel.
  ///
  /// Returns a broadcast [Stream]; multiple listeners are supported. Each
  /// listener sees every event from the moment it subscribes.
  static Stream<MixpanelEvent> get events => _controller.stream;

  /// Internal entry point — invoked by `mixpanel_flutter`'s plugin after
  /// the native SDK has tracked and decorated an event.
  ///
  /// Application code should never call this directly. It is left public
  /// (rather than library-private) so the `mixpanel_flutter` package can
  /// reach it without circular imports.
  static void notifyListeners({
    required String eventName,
    Map<String, Object?>? properties,
  }) {
    _controller.add(
      MixpanelEvent(eventName: eventName, properties: properties),
    );
  }
}

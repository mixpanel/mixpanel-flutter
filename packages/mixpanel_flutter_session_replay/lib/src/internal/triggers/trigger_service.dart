// MixpanelEventBridge.events is @internal but explicitly reserved for
// Mixpanel-authored downstream packages like this one.
// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';

import 'package:mixpanel_flutter_common/mixpanel_flutter_common.dart';

import '../../models/event_trigger.dart';
import '../logger.dart';
import 'event_trigger_evaluator.dart';

/// Subscribes to [MixpanelEventBridge.events] when triggers are configured
/// and fires a callback when a tracked event matches a server-configured
/// Event Trigger.
///
/// Lifecycle is implicit in [updateTriggers]: a non-empty trigger map
/// activates the bridge subscription, a null/empty map cancels it. This
/// matches the native Android/iOS pattern where the upstream event
/// collection only runs while triggers exist.
///
/// The callback (`onTriggerFired`) is invoked with the trigger's sampling
/// percentage. The coordinator wires it to its own `startRecording`, which
/// handles the sampling decision, double-start guards, and the
/// remote-disabled check.
final class TriggerService {
  TriggerService({
    required MixpanelLogger logger,
    required void Function(double percentage) onTriggerFired,
  }) : _logger = logger,
       _onTriggerFired = onTriggerFired,
       _evaluator = EventTriggerEvaluator(const {}, logger);

  final MixpanelLogger _logger;
  final void Function(double percentage) _onTriggerFired;

  EventTriggerEvaluator _evaluator;
  StreamSubscription<MixpanelEvent>? _subscription;
  bool _isDisposed = false;
  bool _isEnabled = true;

  /// Whether event trigger evaluation is currently active.
  bool get isEnabled => _isEnabled;

  /// Pause event-triggered recording without unsubscribing. Matched events
  /// are ignored until [enable] is called. Does not affect manual
  /// `startRecording()` / `stopRecording()` or auto-record.
  void disable() {
    _isEnabled = false;
    _logger.info('Event triggers disabled', tag: 'triggers');
  }

  /// Resume event-triggered recording. Triggers are enabled by default at
  /// SDK initialization.
  void enable() {
    _isEnabled = true;
    _logger.info('Event triggers enabled', tag: 'triggers');
  }

  /// Replace the active trigger set. A non-empty map activates the bridge
  /// subscription; a null/empty map cancels it. Safe to call repeatedly.
  void updateTriggers(Map<String, EventTrigger>? triggers) {
    if (_isDisposed) return;
    _evaluator = EventTriggerEvaluator(triggers ?? const {}, _logger);
    _logger.debug(
      'Updated triggers (${triggers?.length ?? 0} active)',
      tag: 'triggers',
    );
    if (triggers != null && triggers.isNotEmpty) {
      _ensureSubscribed();
    } else {
      _cancelSubscription();
    }
  }

  void _ensureSubscribed() {
    if (_subscription != null) return;
    _subscription = MixpanelEventBridge.events.listen(
      _onEvent,
      onError: (Object error, StackTrace stack) {
        // Never let a bridge error crash the host app.
        _logger.error(
          'MixpanelEventBridge stream error',
          error,
          stack,
          'triggers',
        );
      },
    );
    _logger.info('Subscribed to MixpanelEventBridge.events', tag: 'triggers');
  }

  void _cancelSubscription() {
    if (_subscription == null) return;
    _subscription!.cancel();
    _subscription = null;
    _logger.info(
      'Unsubscribed from MixpanelEventBridge.events',
      tag: 'triggers',
    );
  }

  void _onEvent(MixpanelEvent event) {
    if (!_isEnabled) {
      _logger.debug(
        "Event triggers disabled, ignoring event: '${event.eventName}'",
        tag: 'triggers',
      );
      return;
    }
    final percentage = _evaluator.shouldStartRecording(
      event.eventName,
      event.properties,
    );
    if (percentage == null) return;
    _logger.info(
      "Trigger fired for '${event.eventName}' at $percentage%",
      tag: 'triggers',
    );
    _onTriggerFired(percentage);
  }

  Future<void> dispose() async {
    _isDisposed = true;
    await _subscription?.cancel();
    _subscription = null;
  }
}

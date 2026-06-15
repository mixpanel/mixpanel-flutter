import 'dart:convert';

import 'package:mixpanel_flutter_common/mixpanel_flutter_common.dart';

import '../../models/event_trigger.dart';
import '../logger.dart';

/// Decides whether a tracked event should start session replay recording.
final class EventTriggerEvaluator {
  EventTriggerEvaluator(this._triggers, this._logger);

  final Map<String, EventTrigger> _triggers;
  final MixpanelLogger _logger;

  /// Returns the sampling percentage to pass to `startRecording` on a match,
  /// or `null` if recording should not start.
  double? shouldStartRecording(
    String eventName,
    Map<String, Object?>? properties,
  ) {
    final trigger = _triggers[eventName];
    if (trigger == null) return null;

    final filters = trigger.propertyFilters;
    if (filters != null &&
        !_passesPropertyFilters(filters, properties ?? const {})) {
      return null;
    }

    final percentage = trigger.percentage;
    if (percentage.isNaN || percentage < 0 || percentage > 100) {
      _logger.warning(
        "Invalid trigger percentage for '$eventName': $percentage "
        '(expected 0-100)',
        tag: 'triggers',
      );
      return null;
    }
    return percentage;
  }

  bool _passesPropertyFilters(
    Map<String, dynamic> filters,
    Map<String, Object?> properties,
  ) {
    try {
      final rule = JsonLogicParser.parse(jsonEncode(filters));
      final result = JsonLogicEvaluator.evaluate(rule, properties);
      return result is bool && result;
    } catch (e, stack) {
      // Fail closed: any parse or evaluation error means don't record.
      _logger.error('JSONLogic evaluation failed', e, stack, 'triggers');
      return false;
    }
  }
}

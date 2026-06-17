/// Configuration for a single Mixpanel Event Trigger.
///
/// Triggers are delivered keyed by event name in
/// `sdk_config.config.recording_event_triggers` and fire `startRecording` on
/// match. [percentage] is the per-trigger sampling rate (independent of the
/// global `record_sessions_percent`); [propertyFilters] is an optional
/// JSONLogic expression that must evaluate to true against the event's
/// properties.
final class EventTrigger {
  const EventTrigger({required this.percentage, this.propertyFilters});

  /// Sampling percentage (0–100). Invalid values cause the trigger to be
  /// skipped at evaluation time.
  final double percentage;

  /// Raw JSONLogic expression to apply to event properties. `null` means no
  /// filtering — any tracked event with this name matches.
  final Map<String, dynamic>? propertyFilters;

  factory EventTrigger.fromJson(Map<String, dynamic> json) {
    return EventTrigger(
      percentage: (json['percentage'] as num).toDouble(),
      propertyFilters: json['property_filters'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
    'percentage': percentage,
    if (propertyFilters != null) 'property_filters': propertyFilters,
  };

  @override
  String toString() =>
      'EventTrigger(percentage: $percentage, propertyFilters: $propertyFilters)';
}

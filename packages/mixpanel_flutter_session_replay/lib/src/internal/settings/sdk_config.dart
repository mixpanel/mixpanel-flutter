import '../../models/event_trigger.dart';

/// Parsed SDK config from the remote settings endpoint.
class SdkConfig {
  final double? recordSessionsPercent;

  /// Event-name-keyed map of trigger configurations. When a tracked event's
  /// name matches a key here, [EventTrigger.propertyFilters] is evaluated
  /// against the event's properties; on match, recording is started with
  /// [EventTrigger.percentage] as the sampling rate.
  ///
  /// Wire field: `recording_event_triggers`.
  final Map<String, EventTrigger>? recordingEventTriggers;

  const SdkConfig({this.recordSessionsPercent, this.recordingEventTriggers});

  factory SdkConfig.fromJson(Map<String, dynamic> json) {
    return SdkConfig(
      recordSessionsPercent: (json['record_sessions_percent'] as num?)
          ?.toDouble(),
      recordingEventTriggers: _parseTriggers(json['recording_event_triggers']),
    );
  }

  static Map<String, EventTrigger>? _parseTriggers(Object? raw) {
    if (raw is! Map) return null;
    final triggers = <String, EventTrigger>{};
    raw.forEach((key, value) {
      if (key is String && value is Map) {
        triggers[key] = EventTrigger.fromJson(value.cast<String, dynamic>());
      }
    });
    return triggers.isEmpty ? null : triggers;
  }

  Map<String, dynamic> toJson() => {
    if (recordSessionsPercent != null)
      'record_sessions_percent': recordSessionsPercent,
    if (recordingEventTriggers != null)
      'recording_event_triggers': {
        for (final entry in recordingEventTriggers!.entries)
          entry.key: entry.value.toJson(),
      },
  };
}

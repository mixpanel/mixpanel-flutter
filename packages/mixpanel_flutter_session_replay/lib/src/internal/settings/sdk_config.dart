import '../../models/event_trigger.dart';

/// Parsed SDK config from the remote settings endpoint.
class SdkConfig {
  final double? recordSessionsPercent;

  /// Web recording limits, in milliseconds. Absent or invalid values leave
  /// the app-provided `WebOptions` limits in effect.
  final int? recordMaxMs;
  final int? recordIdleTimeoutMs;

  /// Event-name-keyed map of trigger configurations. When a tracked event's
  /// name matches a key here, [EventTrigger.propertyFilters] is evaluated
  /// against the event's properties; on match, recording is started with
  /// [EventTrigger.percentage] as the sampling rate.
  ///
  /// Wire field: `recording_event_triggers`.
  final Map<String, EventTrigger>? recordingEventTriggers;

  const SdkConfig({
    this.recordSessionsPercent,
    this.recordMaxMs,
    this.recordIdleTimeoutMs,
    this.recordingEventTriggers,
  });

  factory SdkConfig.fromJson(Map<String, dynamic> json) {
    return SdkConfig(
      recordSessionsPercent: (json['record_sessions_percent'] as num?)
          ?.toDouble(),
      recordMaxMs: _positiveMilliseconds(json['record_max_ms']),
      recordIdleTimeoutMs: _positiveMilliseconds(
        json['record_idle_timeout_ms'],
      ),
      recordingEventTriggers: _parseTriggers(json['recording_event_triggers']),
    );
  }

  static int? _positiveMilliseconds(Object? raw) {
    // Duration stores microseconds in a signed 64-bit integer.
    if (raw is! num || !raw.isFinite || raw <= 0 || raw > 9223372036854) {
      return null;
    }
    final milliseconds = raw.toInt();
    return milliseconds > 0 ? milliseconds : null;
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
    if (recordMaxMs != null) 'record_max_ms': recordMaxMs,
    if (recordIdleTimeoutMs != null)
      'record_idle_timeout_ms': recordIdleTimeoutMs,
    if (recordingEventTriggers != null)
      'recording_event_triggers': {
        for (final entry in recordingEventTriggers!.entries)
          entry.key: entry.value.toJson(),
      },
  };
}

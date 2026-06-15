import 'package:clock/clock.dart';
import 'package:uuid/uuid.dart';

/// Session status enum
enum SessionStatus {
  /// Currently recording
  active,

  /// Session completed
  ended,
}

/// Represents a continuous recording period
class Session {
  /// Unique session ID (UUID v4)
  final String id;

  /// Session start timestamp (UTC)
  final DateTime startTime;

  /// Session end timestamp (null if active)
  DateTime? endTime;

  /// Current session state
  SessionStatus status;

  /// Last interaction/capture timestamp
  DateTime lastActivityTime;

  /// Number of events in this session
  int eventCount;

  Session({
    required this.id,
    required this.startTime,
    this.endTime,
    this.status = SessionStatus.active,
    DateTime? lastActivityTime,
    this.eventCount = 0,
  }) : lastActivityTime = lastActivityTime ?? startTime;

  /// Update activity timestamp to current time
  void recordActivity() {
    lastActivityTime = clock.now();
  }

  /// Generate a new unique session ID (UUID v4 format)
  static String generateId() {
    return const Uuid().v4();
  }

  /// Serialize session to JSON for storage
  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'status': status.name,
    'lastActivityTime': lastActivityTime.toIso8601String(),
    'eventCount': eventCount,
  };

  /// Deserialize session from JSON
  factory Session.fromJson(Map<String, dynamic> json) => Session(
    id: json['id'] as String,
    startTime: DateTime.parse(json['startTime'] as String),
    endTime: json['endTime'] != null
        ? DateTime.parse(json['endTime'] as String)
        : null,
    status: SessionStatus.values.byName(json['status'] as String),
    lastActivityTime: DateTime.parse(json['lastActivityTime'] as String),
    eventCount: json['eventCount'] as int,
  );

  @override
  String toString() {
    return 'Session(id: $id, status: $status, '
        'eventCount: $eventCount, startTime: $startTime)';
  }
}

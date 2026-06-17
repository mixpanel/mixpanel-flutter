import 'package:logging/logging.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';

/// Represents a single log entry from the SDK
class LogEntry {
  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
  });

  /// When the log was created
  final DateTime timestamp;

  /// Log level (debug, info, warning, error)
  final LogLevel level;

  /// Log message
  final String message;

  /// Optional error object
  final Object? error;

  /// Optional stack trace
  final StackTrace? stackTrace;

  /// Create LogEntry from Dart's logging.LogRecord
  factory LogEntry.fromLogRecord(LogRecord record) {
    return LogEntry(
      timestamp: record.time,
      level: _mapLevel(record.level),
      message: record.message,
      error: record.error,
      stackTrace: record.stackTrace,
    );
  }

  /// Map Dart's logging Level to SDK LogLevel
  static LogLevel _mapLevel(Level dartLevel) {
    if (dartLevel >= Level.SEVERE) return LogLevel.error;
    if (dartLevel >= Level.WARNING) return LogLevel.warning;
    if (dartLevel >= Level.INFO) return LogLevel.info;
    return LogLevel.debug;
  }
}

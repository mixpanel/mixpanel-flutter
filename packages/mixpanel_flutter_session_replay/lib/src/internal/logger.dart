import 'package:logging/logging.dart';
import '../models/configuration.dart';

/// Internal logger for Mixpanel Session Replay SDK
///
/// Uses a singleton logger shared across all SDK instances. This ensures:
/// - No duplicate console output
/// - All logs are captured (even from improperly cleaned up instances)
/// - Simpler lifecycle management
class MixpanelLogger {
  // Singleton logger shared by all SDK instances
  static final Logger _logger = Logger('mixpanel.session_replay');

  // Track whether console output has been initialized
  static bool _consoleInitialized = false;

  final LogLevel _level;

  /// Create a logger instance with the specified log level
  ///
  /// [level] The minimum log level to output
  MixpanelLogger(this._level) {
    // Enable hierarchical logging to allow setting levels on non-root loggers
    hierarchicalLoggingEnabled = true;

    // Set up console output once globally (never disposed)
    if (!_consoleInitialized && _level != LogLevel.none) {
      _consoleInitialized = true;
      _logger.onRecord.listen((record) {
        // ignore: avoid_print
        print('[${record.level.name}] ${record.loggerName}: ${record.message}');
      });
    }

    // Map our LogLevel enum to Dart's logging Level
    final dartLevel = _mapLogLevel(_level);

    // Set the logger to the most verbose level requested by any instance
    // This ensures we don't miss logs from any SDK instance
    if (_logger.level > dartLevel) {
      _logger.level = dartLevel;
    }
  }

  /// Map our LogLevel enum to Dart's logging Level
  static Level _mapLogLevel(LogLevel level) {
    switch (level) {
      case LogLevel.none:
        return Level.OFF;
      case LogLevel.error:
        return Level.SEVERE;
      case LogLevel.warning:
        return Level.WARNING;
      case LogLevel.info:
        return Level.INFO;
      case LogLevel.debug:
        return Level.FINE;
    }
  }

  /// Log a debug message (verbose)
  void debug(String message, {String? tag}) {
    final formattedMessage = tag != null ? '[$tag] $message' : message;
    _logger.fine(formattedMessage);
  }

  /// Log an info message
  void info(String message, {String? tag}) {
    final formattedMessage = tag != null ? '[$tag] $message' : message;
    _logger.info(formattedMessage);
  }

  /// Log a warning message
  void warning(String message, {String? tag}) {
    final formattedMessage = tag != null ? '[$tag] $message' : message;
    _logger.warning(formattedMessage);
  }

  /// Log an error message
  void error(
    String message, [
    Object? error,
    StackTrace? stackTrace,
    String? tag,
  ]) {
    final formattedMessage = tag != null ? '[$tag] $message' : message;
    _logger.severe(formattedMessage, error, stackTrace);
  }

  /// Dispose of the logger and clean up resources
  ///
  /// Note: This is a no-op since the logger is a singleton that lives for
  /// the app lifetime. This ensures all logs are captured, even from
  /// SDK instances that may not have been properly cleaned up.
  void dispose() {
    // Do not dispose the singleton console subscription
  }
}

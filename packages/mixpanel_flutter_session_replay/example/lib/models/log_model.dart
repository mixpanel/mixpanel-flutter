import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:logging/logging.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';

import 'log_entry.dart';

// Global log storage that starts capturing immediately
final List<LogEntry> _globalLogs = [];
StreamSubscription<LogRecord>? _globalLogSubscription;

/// Start capturing logs globally before the app starts
void startGlobalLogCapture() {
  _globalLogSubscription = Logger.root.onRecord.listen((record) {
    // Filter to only Mixpanel SDK logs
    if (record.loggerName.startsWith('mixpanel.')) {
      final entry = LogEntry.fromLogRecord(record);
      _globalLogs.add(entry);

      // Keep logs under control
      if (_globalLogs.length > 10000) {
        _globalLogs.removeRange(0, 1000);
      }
    }
  });
}

/// Manages SDK log capture and filtering
class LogModel extends ChangeNotifier {
  LogModel() {
    // Copy existing logs captured before LogModel was created
    _logs.addAll(_globalLogs);

    // Cancel the global subscription since LogModel is now handling it
    _globalLogSubscription?.cancel();
    _globalLogSubscription = null;

    // Continue listening for new logs
    Logger.root.onRecord.listen((record) {
      // Filter to only Mixpanel SDK logs
      if (record.loggerName.startsWith('mixpanel.')) {
        final entry = LogEntry.fromLogRecord(record);
        _logs.add(entry);

        // Keep logs under control
        if (_logs.length > 10000) {
          _logs.removeRange(0, 1000);
        }

        // Batch notifications to avoid excessive rebuilds
        _scheduleBatchedNotification();
      }
    });
  }

  final List<LogEntry> _logs = [];
  LogLevel _filterLevel = LogLevel.debug;
  Timer? _batchNotifyTimer;
  bool _hasPendingNotification = false;

  /// All logs (unfiltered)
  List<LogEntry> get allLogs => List.unmodifiable(_logs);

  /// Logs filtered by current filter level
  List<LogEntry> get filteredLogs {
    return _logs.where((log) {
      return log.level.index <= _filterLevel.index &&
          log.level != LogLevel.none;
    }).toList();
  }

  /// Current filter level
  LogLevel get filterLevel => _filterLevel;

  /// Clear all logs
  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  /// Set filter level
  void setFilterLevel(LogLevel level) {
    _filterLevel = level;
    notifyListeners();
  }

  /// Schedule a batched notification to avoid excessive UI updates
  void _scheduleBatchedNotification() {
    if (_hasPendingNotification) return;

    _hasPendingNotification = true;
    _batchNotifyTimer?.cancel();

    _batchNotifyTimer = Timer(const Duration(milliseconds: 500), () {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
        _hasPendingNotification = false;
      });
    });
  }

  @override
  void dispose() {
    _batchNotifyTimer?.cancel();
    super.dispose();
  }
}

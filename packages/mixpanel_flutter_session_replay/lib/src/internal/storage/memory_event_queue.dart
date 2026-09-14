import '../../models/session.dart';
import '../../models/session_event.dart';
import '../logger.dart';
import 'event_queue_interface.dart';

/// Last-resort queue used when browser persistence is unavailable.
///
/// It preserves capture and upload for the current page lifetime, but cannot
/// resume after navigation or a reload.
class MemoryEventQueue implements EventQueue {
  final int quotaMB;
  final MixpanelLogger _logger;
  final List<PersistedSessionReplayEvent> _events = [];
  final Map<String, Session> _sessions = {};
  final Map<String, int> _sequenceNumbers = {};
  var _nextId = 1;
  var _sizeBytes = 0;
  var _disposed = false;

  MemoryEventQueue({required this.quotaMB, required MixpanelLogger logger})
    : _logger = logger;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> add(SessionReplayEvent event) async {
    _checkState();
    final row = event.toDbRow()..['id'] = _nextId;
    final persisted = PersistedSessionReplayEvent.fromDbRow(row);
    final quotaBytes = quotaMB * 1024 * 1024;
    if (_sizeBytes + persisted.dataSize > quotaBytes) {
      _logger.warning('In-memory replay queue quota exceeded; dropping event');
      return;
    }
    _nextId++;
    _events.add(persisted);
    _sizeBytes += persisted.dataSize;
  }

  @override
  Future<void> createSessionMetadata(Session session) async {
    _checkState();
    _sessions.putIfAbsent(session.id, () => session);
    _sequenceNumbers.putIfAbsent(session.id, () => -1);
  }

  @override
  Future<PersistedSessionReplayEvent?> fetchOldest() async {
    _checkState();
    return _events.isEmpty ? null : _events.first;
  }

  @override
  Future<PersistedSessionReplayEvent?> fetchNewest() async {
    _checkState();
    return _events.isEmpty ? null : _events.last;
  }

  @override
  Future<QueuedEventHeader?> fetchOldestHeader() async {
    _checkState();
    return _events.isEmpty ? null : _headerFor(_events.first);
  }

  @override
  Future<QueuedEventHeader?> fetchNewestHeader() async {
    _checkState();
    return _events.isEmpty ? null : _headerFor(_events.last);
  }

  QueuedEventHeader _headerFor(PersistedSessionReplayEvent event) {
    return QueuedEventHeader(
      id: event.id,
      sessionId: event.sessionId,
      distinctId: event.distinctId,
      timestamp: event.timestamp,
    );
  }

  @override
  Future<List<PersistedSessionReplayEvent>> fetchBatch({
    required String sessionId,
    required String distinctId,
    required int maxBytes,
    required int maxCount,
  }) async {
    _checkState();
    final batch = <PersistedSessionReplayEvent>[];
    var bytes = 0;
    for (final event in _events) {
      if (event.sessionId != sessionId) continue;
      if (event.distinctId != distinctId) break;
      if (batch.isNotEmpty &&
          (batch.length >= maxCount || bytes + event.dataSize > maxBytes)) {
        break;
      }
      batch.add(event);
      bytes += event.dataSize;
    }
    return batch;
  }

  @override
  Future<Session?> getSessionMetadata(String sessionId) async {
    _checkState();
    return _sessions[sessionId];
  }

  @override
  Future<void> remove(List<PersistedSessionReplayEvent> events) async {
    _checkState();
    final ids = events.map((event) => event.id).toSet();
    _events.removeWhere((event) {
      if (!ids.contains(event.id)) return false;
      _sizeBytes -= event.dataSize;
      return true;
    });
  }

  @override
  Future<void> removeAll() async {
    _checkState();
    _events.clear();
    _sessions.clear();
    _sequenceNumbers.clear();
    _sizeBytes = 0;
  }

  @override
  Future<int> getLastSequenceNumber(String sessionId) async {
    _checkState();
    return _sequenceNumbers[sessionId] ?? -1;
  }

  @override
  Future<void> updateSequenceNumber(
    String sessionId,
    int sequenceNumber,
  ) async {
    _checkState();
    if (!_sessions.containsKey(sessionId)) {
      throw StateError('Session metadata not found for session $sessionId');
    }
    _sequenceNumbers[sessionId] = sequenceNumber;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _events.clear();
    _sessions.clear();
    _sequenceNumbers.clear();
    _sizeBytes = 0;
  }

  void _checkState() {
    if (_disposed) throw StateError('EventQueue has been disposed');
  }
}

import 'package:mixpanel_flutter_session_replay/src/internal/storage/event_queue_interface.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session_event.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session.dart';

/// In-memory implementation of EventQueue for testing
///
/// Provides a simple, fast, and predictable queue implementation
/// without requiring SQLite or platform channels.
class InMemoryEventQueue implements EventQueue {
  final List<PersistedSessionReplayEvent> _events = [];
  final Map<String, Session> _sessionMetadata = {};
  final Map<String, int> _sequenceNumbers = {};

  int _nextId = 1;
  bool _disposed = false;

  @override
  Future<void> initialize() async {
    // No-op for in-memory implementation
  }

  @override
  Future<void> add(SessionReplayEvent event) async {
    _checkNotDisposed();

    // Rough estimate of data size for batching
    final dataSize = _estimatePayloadSize(event.payload);

    _events.add(
      PersistedSessionReplayEvent(
        id: _nextId++,
        dataSize: dataSize,
        sessionId: event.sessionId,
        distinctId: event.distinctId,
        timestamp: event.timestamp,
        type: event.type,
        payload: event.payload,
      ),
    );
  }

  /// Estimate payload size in bytes (rough approximation)
  int _estimatePayloadSize(EventPayload payload) {
    if (payload is ScreenshotPayload) {
      return payload.imageData.length; // JPEG bytes
    } else if (payload is InteractionPayload) {
      return 100; // Small JSON object
    } else if (payload is MetadataPayload) {
      return 50; // Small metadata
    }
    return 100; // Default estimate
  }

  @override
  Future<void> createSessionMetadata(Session session) async {
    _checkNotDisposed();
    if (!_sessionMetadata.containsKey(session.id)) {
      _sessionMetadata[session.id] = session;
    }
  }

  @override
  Future<PersistedSessionReplayEvent?> fetchOldest() async {
    _checkNotDisposed();
    if (_events.isEmpty) return null;
    return _events.first;
  }

  @override
  Future<PersistedSessionReplayEvent?> fetchNewest() async {
    _checkNotDisposed();
    if (_events.isEmpty) return null;
    return _events.last;
  }

  @override
  Future<List<PersistedSessionReplayEvent>> fetchBatch({
    required String sessionId,
    required String distinctId,
    required int maxBytes,
    required int maxCount,
  }) async {
    _checkNotDisposed();

    final batch = <PersistedSessionReplayEvent>[];
    int totalBytes = 0;

    for (final event in _events) {
      if (event.sessionId != sessionId || event.distinctId != distinctId) {
        break;
      }

      // Use the dataSize field from the persisted event
      if (batch.isNotEmpty &&
          (totalBytes + event.dataSize > maxBytes ||
              batch.length >= maxCount)) {
        break;
      }

      batch.add(event);
      totalBytes += event.dataSize;
    }

    return batch;
  }

  @override
  Future<Session?> getSessionMetadata(String sessionId) async {
    _checkNotDisposed();
    return _sessionMetadata[sessionId];
  }

  @override
  Future<void> remove(List<PersistedSessionReplayEvent> events) async {
    _checkNotDisposed();
    final idsToRemove = events.map((e) => e.id).toSet();
    _events.removeWhere((e) => idsToRemove.contains(e.id));
  }

  @override
  Future<void> removeAll() async {
    _checkNotDisposed();
    _events.clear();
    _sessionMetadata.clear();
    _sequenceNumbers.clear();
  }

  @override
  Future<int> getLastSequenceNumber(String sessionId) async {
    _checkNotDisposed();
    return _sequenceNumbers[sessionId] ?? -1;
  }

  @override
  Future<void> updateSequenceNumber(
    String sessionId,
    int sequenceNumber,
  ) async {
    _checkNotDisposed();
    if (!_sessionMetadata.containsKey(sessionId)) {
      throw StateError('Session metadata not found for session $sessionId');
    }
    _sequenceNumbers[sessionId] = sequenceNumber;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _events.clear();
    _sessionMetadata.clear();
    _sequenceNumbers.clear();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('EventQueue has been disposed');
    }
  }

  // Test helpers
  int get eventCount => _events.length;
  bool get isDisposed => _disposed;
}

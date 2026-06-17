import '../../models/session_event.dart';
import '../../models/session.dart';

/// Abstract interface for event queue implementations
///
/// Implementations can use different storage mechanisms (SQLite, in-memory, file-based, etc.)
/// based on platform capabilities and requirements.
abstract class EventQueue {
  /// Initialize the queue
  Future<void> initialize();

  /// Add an event to the queue
  Future<void> add(SessionReplayEvent event);

  /// Create session metadata in upload_metadata table
  ///
  /// Called when a session starts recording to store the session start time.
  /// This allows us to reconstruct the correct replay_start_time for old sessions.
  /// If metadata already exists for this session, this is a no-op.
  Future<void> createSessionMetadata(Session session);

  /// Get the oldest event across all sessions (for age checking)
  /// Returns null if no events exist
  Future<PersistedSessionReplayEvent?> fetchOldest();

  /// Get the newest event across all sessions (for flush cutoff)
  /// Returns null if no events exist
  Future<PersistedSessionReplayEvent?> fetchNewest();

  /// Fetch batch of consecutive events for a specific sessionId and distinctId
  ///
  /// Returns consecutive events with the same sessionId and distinctId,
  /// up to [maxBytes] total payload size or [maxCount] events,
  /// whichever limit is reached first.
  ///
  /// Stops at the first event where distinctId changes (boundary detection).
  Future<List<PersistedSessionReplayEvent>> fetchBatch({
    required String sessionId,
    required String distinctId,
    required int maxBytes,
    required int maxCount,
  });

  /// Get session metadata for a given session ID
  ///
  /// Reconstructs a Session object from the upload_metadata table.
  /// Returns null if no metadata exists for the session.
  /// Used to get Session objects for old sessions during upload.
  Future<Session?> getSessionMetadata(String sessionId);

  /// Remove specific events from the queue (after successful upload)
  Future<void> remove(List<PersistedSessionReplayEvent> events);

  /// Clear all events and metadata from the queue
  Future<void> removeAll();

  /// Get the last sequence number for a session
  /// Returns -1 if no sequence number exists for the session
  Future<int> getLastSequenceNumber(String sessionId);

  /// Update sequence number after successful upload
  ///
  /// Throws StateError if session metadata doesn't exist.
  /// Session metadata must be created via createSessionMetadata() before calling this.
  Future<void> updateSequenceNumber(String sessionId, int sequenceNumber);

  /// Dispose resources
  Future<void> dispose();
}

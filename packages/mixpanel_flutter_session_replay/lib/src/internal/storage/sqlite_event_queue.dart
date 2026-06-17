import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/session_event.dart';
import '../../models/session.dart';
import '../logger.dart';
import 'event_queue_interface.dart';

/// SQLite-based event queue implementation
///
/// Stores events in a token-specific SQLite database with efficient indexing.
/// Supports cumulative batch fetching (N screenshots + all interactions up to Nth).
class SqliteEventQueue implements EventQueue {
  final String _token;
  final Directory? _storageDir;
  final int quotaMB;
  final MixpanelLogger _logger;

  Database? _db;

  SqliteEventQueue({
    required String token,
    Directory? storageDir,
    this.quotaMB = 50,
    required MixpanelLogger logger,
  }) : _token = token,
       _storageDir = storageDir,
       _logger = logger;

  @override
  Future<void> initialize() async {
    _logger.debug('Initializing SQLite event storage...');

    // Open SQLite database (token-specific)
    final dbPath = await _getDatabasePath();
    _logger.debug('Database path: $dbPath');

    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: _createTables,
      onConfigure: (db) async {
        // Enable WAL mode for concurrency
        final result = await db.rawQuery('PRAGMA journal_mode=WAL');
        _logger.debug('WAL mode enabled: $result');
      },
    );

    _logger.info('SQLite event storage initialized');
  }

  Future<void> _createTables(Database db, int version) async {
    _logger.debug('Creating database tables...');

    // Events table: stores screenshots and interactions
    await db.execute('''
      CREATE TABLE events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        distinct_id TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        type INTEGER NOT NULL,
        payload_metadata TEXT,
        payload_binary BLOB,
        data_size INTEGER NOT NULL
      )
    ''');

    // Upload metadata: tracks sequence numbers for batch uploads per session
    await db.execute('''
      CREATE TABLE upload_metadata (
        session_id TEXT PRIMARY KEY,
        last_sequence_number INTEGER NOT NULL DEFAULT -1,
        session_start_time INTEGER NOT NULL
      )
    ''');

    // Index for efficient batch fetching
    await db.execute('''
      CREATE INDEX idx_session_distinct_type_timestamp
      ON events(session_id, distinct_id, type, timestamp)
    ''');

    // Index for session cleanup (find old sessions)
    await db.execute('''
      CREATE INDEX idx_session_start_time
      ON upload_metadata(session_start_time)
    ''');

    _logger.debug('Database tables created');
  }

  @override
  Future<void> add(SessionReplayEvent event) async {
    if (_db == null) {
      throw StateError('Queue not initialized');
    }

    // Serialize event to get data size
    final eventRow = event.toDbRow();
    final eventSize = eventRow['data_size'] as int;

    // Check quota before inserting
    final quotaBytes = quotaMB * 1024 * 1024;
    final result = await _db!.rawQuery(
      'SELECT SUM(data_size) as total FROM events',
    );
    final currentSize = result.first['total'] as int? ?? 0;

    if (currentSize + eventSize > quotaBytes) {
      _logger.warning(
        'Queue quota exceeded ($currentSize + $eventSize > $quotaBytes), dropping event',
      );
      return; // Drop the event instead of inserting
    }

    // Insert into database
    await _db!.insert('events', eventRow);
  }

  @override
  Future<void> createSessionMetadata(Session session) async {
    if (_db == null) {
      throw StateError('Queue not initialized');
    }

    final existing = await _db!.query(
      'upload_metadata',
      where: 'session_id = ?',
      whereArgs: [session.id],
    );

    if (existing.isEmpty) {
      // First time creating metadata for this session
      await _db!.insert('upload_metadata', {
        'session_id': session.id,
        'last_sequence_number': -1, // No uploads yet
        'session_start_time': session.startTime.millisecondsSinceEpoch,
      });
      _logger.debug(
        'Created session metadata for ${session.id} (start: ${session.startTime.millisecondsSinceEpoch})',
      );
    }
    // If metadata exists, don't update (session_start_time is immutable)
  }

  @override
  Future<PersistedSessionReplayEvent?> fetchOldest() async {
    if (_db == null) {
      throw StateError('Storage not initialized');
    }

    // Get the oldest event across all sessions (for age checking)
    final rows = await _db!.query('events', orderBy: 'id ASC', limit: 1);

    if (rows.isEmpty) return null;

    return PersistedSessionReplayEvent.fromDbRow(rows.first);
  }

  @override
  Future<PersistedSessionReplayEvent?> fetchNewest() async {
    if (_db == null) {
      throw StateError('Storage not initialized');
    }

    // Get the newest event across all sessions (for flush cutoff)
    final rows = await _db!.query('events', orderBy: 'id DESC', limit: 1);

    if (rows.isEmpty) return null;

    return PersistedSessionReplayEvent.fromDbRow(rows.first);
  }

  @override
  Future<List<PersistedSessionReplayEvent>> fetchBatch({
    required String sessionId,
    required String distinctId,
    required int maxBytes,
    required int maxCount,
  }) async {
    if (_db == null) {
      throw StateError('Storage not initialized');
    }

    // Get CONSECUTIVE events for the given sessionId and distinctId,
    // stopping at the first event where distinctId changes.
    //
    // This ensures we don't mix different users in the same upload batch.

    // Step 1: Find the boundary - first event where distinctId changes
    final boundaryId = await _findDistinctIdBoundary(sessionId, distinctId);

    // Step 2: Fetch events with size filtering
    final rows = await _fetchEventsWithSizeLimit(
      sessionId: sessionId,
      boundaryId: boundaryId,
      maxBytes: maxBytes,
      maxCount: maxCount,
    );

    return rows
        .map((row) => PersistedSessionReplayEvent.fromDbRow(row))
        .toList();
  }

  /// Find the first event ID where distinctId changes (boundary detection)
  Future<int?> _findDistinctIdBoundary(
    String sessionId,
    String distinctId,
  ) async {
    final rows = await _db!.rawQuery(
      '''
      SELECT MIN(id) as boundary_id
      FROM events
      WHERE session_id = ?
        AND distinct_id != ?
      ''',
      [sessionId, distinctId],
    );

    if (rows.isEmpty || rows.first['boundary_id'] == null) {
      return null;
    }

    return rows.first['boundary_id'] as int;
  }

  /// Fetch events with cumulative size limit (uses correlated subquery for running totals)
  Future<List<Map<String, Object?>>> _fetchEventsWithSizeLimit({
    required String sessionId,
    required int? boundaryId,
    required int maxBytes,
    required int maxCount,
  }) async {
    // Use a very large number as the boundary if none exists
    // This allows us to use a single query for both cases
    final effectiveBoundary =
        boundaryId ?? 9223372036854775807; // Max 64-bit int

    return await _db!.rawQuery(
      '''
      SELECT id, session_id, distinct_id, timestamp, type, payload_metadata, payload_binary, data_size
      FROM (
        SELECT
          id, session_id, distinct_id, timestamp, type, payload_metadata, payload_binary, data_size,
          (SELECT SUM(e2.data_size)
           FROM events e2
           WHERE e2.session_id = events.session_id
             AND e2.id < ?
             AND e2.id <= events.id) as running_total
        FROM events
        WHERE session_id = ?
          AND id < ?
        ORDER BY id ASC
        LIMIT ?
      )
      WHERE running_total <= ?
      ''',
      [effectiveBoundary, sessionId, effectiveBoundary, maxCount, maxBytes],
    );
  }

  @override
  Future<void> remove(List<PersistedSessionReplayEvent> events) async {
    if (_db == null) {
      throw StateError('Queue not initialized');
    }

    if (events.isEmpty) return;

    // Extract database IDs from PersistedSessionReplayEvent
    final eventIds = events.map((e) => e.id).toList();

    // Delete events in a single query
    await _db!.delete(
      'events',
      where: 'id IN (${List.filled(eventIds.length, '?').join(',')})',
      whereArgs: eventIds,
    );

    _logger.debug('Removed ${events.length} events');
  }

  @override
  Future<void> dispose() async {
    await _db?.close();
    _db = null;
    _logger.debug('SQLite event storage disposed');
  }

  /// Clear event cache - deletes all stored events and metadata
  /// In the future, we can remove this and flush old records on launch
  @override
  Future<void> removeAll() async {
    if (_db == null) {
      throw StateError('Storage not initialized');
    }

    _logger.info('Clearing event database queue...');

    // Clear events table
    await _db!.delete('events');
    _logger.debug('Cleared events table');

    // Clear upload_metadata table
    await _db!.delete('upload_metadata');
    _logger.debug('Cleared upload_metadata table');

    _logger.info('All data cleared from event queue database');
  }

  /// Get the last sequence number for a session
  @override
  Future<int> getLastSequenceNumber(String sessionId) async {
    if (_db == null) {
      throw StateError('Storage not initialized');
    }

    final result = await _db!.query(
      'upload_metadata',
      columns: ['last_sequence_number'],
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );

    if (result.isEmpty) return -1;
    return result.first['last_sequence_number'] as int;
  }

  /// Update sequence number after successful upload
  @override
  Future<void> updateSequenceNumber(
    String sessionId,
    int sequenceNumber,
  ) async {
    if (_db == null) {
      throw StateError('Storage not initialized');
    }

    // Update sequence number - session metadata must already exist
    final count = await _db!.update(
      'upload_metadata',
      {'last_sequence_number': sequenceNumber},
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );

    if (count == 0) {
      throw StateError(
        'Session metadata not found for $sessionId - createSessionMetadata() must be called first',
      );
    }
  }

  /// Get session metadata for a given session ID
  @override
  Future<Session?> getSessionMetadata(String sessionId) async {
    if (_db == null) {
      throw StateError('Storage not initialized');
    }

    final result = await _db!.query(
      'upload_metadata',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );

    if (result.isEmpty) return null;

    final row = result.first;
    return Session(
      id: sessionId,
      startTime: DateTime.fromMillisecondsSinceEpoch(
        row['session_start_time'] as int,
      ),
      status: SessionStatus.ended, // Old sessions are considered ended
    );
  }

  /// Get database path (token-specific, sanitized for filesystem)
  Future<String> _getDatabasePath() async {
    final baseDir = _storageDir ?? await _getDefaultStorageDirectory();
    final sanitizedToken = _sanitizeToken(_token);
    return '${baseDir.path}/mixpanel_replay_$sanitizedToken.db';
  }

  /// Get default storage directory
  Future<Directory> _getDefaultStorageDirectory() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDocDir.path}/mixpanel_replay');
    await dir.create(recursive: true);
    return dir;
  }

  /// Sanitize token for use in filename
  String _sanitizeToken(String token) {
    // Replace any characters that aren't alphanumeric, dash, or underscore
    return token.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }
}

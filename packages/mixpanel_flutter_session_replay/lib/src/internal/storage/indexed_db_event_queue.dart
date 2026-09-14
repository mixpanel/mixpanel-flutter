import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:uuid/uuid.dart';

import 'event_queue_interface.dart';
import '../../models/session_event.dart';
import '../../models/session.dart';
import '../logger.dart';
import 'upload_lease.dart';

const _eventsStore = 'events';
const _metadataStore = 'session_metadata';
const _sessionIndex = 'by_session';
const _eventSizeIndex = 'by_size';
const _eventHeaderIndex = 'by_id_header';
const _eventTimestampIndex = 'by_timestamp';
const _metadataStartIndex = 'by_start_time';
const _coordinationStore = 'coordination';
const _uploadLeaseKey = 'upload_lease';
const _storageSizeKey = 'storage_size';
const _isWasm = bool.fromEnvironment('dart.tool.dart2wasm');

/// Dart2Wasm internalizes JavaScript `null` and `undefined` as Dart `null`, and
/// consequently does not implement `JSAny.isUndefined`. Dart2JS keeps them
/// distinct, so retain the explicit undefined check only on that compiler.
bool _isNullish(JSAny? value) =>
    value == null || (!_isWasm && value.isUndefined);

int _asInt(Object? value) => (value as num).toInt();

int? _asNullableInt(Object? value) =>
    value == null ? null : (value as num).toInt();

/// IndexedDB-backed implementation of [EventQueue] for web.
///
/// Persists events and session metadata in the browser's IndexedDB,
/// surviving page refreshes and tab closures. Uses auto-incrementing
/// keys for FIFO ordering (matching SQLite's AUTOINCREMENT behavior).
class IndexedDbEventQueue
    implements EventQueue, UploadLease, AtomicUploadCommit {
  final String _dbName;
  final MixpanelLogger _logger;
  final String ownerId;
  final int quotaMB;
  web.IDBDatabase? _db;
  bool _disposed = false;

  /// In-memory byte counter for quota enforcement.
  /// Initialized from IndexedDB on startup, updated on add/remove/removeAll.
  int _currentSizeBytes = 0;

  IndexedDbEventQueue({
    required String token,
    this.quotaMB = 50,
    required MixpanelLogger logger,
    String? ownerId,
  }) : _dbName = 'mixpanel_replay_${_sanitizeToken(token)}',
       _logger = logger,
       ownerId = ownerId ?? const Uuid().v4();

  static String _sanitizeToken(String token) =>
      token.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  @override
  Future<void> initialize() async {
    final completer = Completer<void>();
    final request = web.window.indexedDB.open(_dbName, 5);
    Timer? blockedTimer;

    request.onupgradeneeded = (web.IDBVersionChangeEvent event) {
      final db = (event.target as web.IDBRequest).result as web.IDBDatabase;

      final web.IDBObjectStore eventsStore;
      if (!db.objectStoreNames.contains(_eventsStore)) {
        eventsStore = db.createObjectStore(
          _eventsStore,
          web.IDBObjectStoreParameters(keyPath: 'id'.toJS, autoIncrement: true),
        );
      } else {
        eventsStore = request.transaction!.objectStore(_eventsStore);
      }
      if (!eventsStore.indexNames.contains(_sessionIndex)) {
        eventsStore.createIndex(_sessionIndex, 'session_id'.toJS);
      }
      if (!eventsStore.indexNames.contains(_eventSizeIndex)) {
        eventsStore.createIndex(_eventSizeIndex, 'data_size'.toJS);
      }
      if (!eventsStore.indexNames.contains(_eventHeaderIndex)) {
        // A key-only cursor over this composite index returns ordering metadata
        // without structured-cloning payload_binary onto the main isolate.
        eventsStore.createIndex(
          _eventHeaderIndex,
          ['id', 'session_id', 'distinct_id', 'timestamp'].jsify()!,
        );
      }
      if (!eventsStore.indexNames.contains(_eventTimestampIndex)) {
        eventsStore.createIndex(_eventTimestampIndex, 'timestamp'.toJS);
      }

      final web.IDBObjectStore metadataStore;
      if (!db.objectStoreNames.contains(_metadataStore)) {
        metadataStore = db.createObjectStore(
          _metadataStore,
          web.IDBObjectStoreParameters(keyPath: 'session_id'.toJS),
        );
      } else {
        metadataStore = request.transaction!.objectStore(_metadataStore);
      }
      if (!metadataStore.indexNames.contains(_metadataStartIndex)) {
        metadataStore.createIndex(
          _metadataStartIndex,
          'session_start_time'.toJS,
        );
      }

      if (!db.objectStoreNames.contains(_coordinationStore)) {
        db.createObjectStore(
          _coordinationStore,
          web.IDBObjectStoreParameters(keyPath: 'name'.toJS),
        );
      }
    }.toJS;

    request.onsuccess = (web.Event event) {
      blockedTimer?.cancel();
      final openedDb =
          (event.target as web.IDBRequest).result as web.IDBDatabase;
      if (completer.isCompleted) {
        openedDb.close();
        return;
      }
      _db = openedDb;
      _db!.onversionchange = (web.Event event) {
        _logger.info('IndexedDB version changed; closing stale connection');
        _db?.close();
        _db = null;
      }.toJS;
      _logger.debug('IndexedDB opened: $_dbName');
      if (!completer.isCompleted) completer.complete();
    }.toJS;

    request.onerror = (web.Event event) {
      blockedTimer?.cancel();
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Failed to open IndexedDB: $_dbName'),
        );
      }
    }.toJS;

    request.onblocked = (web.Event event) {
      _logger.warning(
        'Opening IndexedDB is waiting for another tab to close: $_dbName',
      );
      blockedTimer ??= Timer(const Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError(
              'Opening IndexedDB was blocked by another tab: $_dbName',
            ),
          );
        }
      });
    }.toJS;

    await completer.future;

    // Synchronize a transactional size record used by every open tab. A
    // process-local counter alone can allow concurrent tabs to exceed quota.
    _currentSizeBytes = await _synchronizeTotalSize();
  }

  @override
  Future<void> add(SessionReplayEvent event) async {
    _checkState();

    final row = event.toDbRow();
    final eventSize = row['data_size'] as int;

    final quotaBytes = quotaMB * 1024 * 1024;
    final txn = _db!.transaction(
      [
        _eventsStore,
        _coordinationStore,
      ].map((store) => store.toJS).toList().toJS,
      'readwrite',
    );
    final eventsStore = txn.objectStore(_eventsStore);
    final coordinationStore = txn.objectStore(_coordinationStore);
    final sizeRequest = coordinationStore.get(_storageSizeKey.toJS);
    var accepted = false;
    var observedSize = _currentSizeBytes;

    sizeRequest.onsuccess = (web.Event event) {
      final result = (event.target as web.IDBRequest).result;
      if (!_isNullish(result)) {
        final record = (result.dartify()! as Map).cast<String, dynamic>();
        observedSize = _asInt(record['bytes']);
      }
      if (observedSize + eventSize > quotaBytes) return;

      accepted = true;
      observedSize += eventSize;
      eventsStore.add(_dartMapToJs(row));
      coordinationStore.put(_storageSizeRecord(observedSize));
    }.toJS;

    await _awaitTransaction(txn);
    _currentSizeBytes = observedSize;

    if (!accepted) {
      _logger.warning(
        'Queue quota exceeded ($observedSize + $eventSize > $quotaBytes), '
        'dropping event',
      );
    }
  }

  @override
  Future<PersistedSessionReplayEvent?> fetchOldest() async {
    _checkState();

    final txn = _db!.transaction(_eventsStore.toJS, 'readonly');
    final store = txn.objectStore(_eventsStore);
    final request = store.openCursor();

    final completer = Completer<PersistedSessionReplayEvent?>();
    request.onsuccess = (web.Event event) {
      final result = (event.target as web.IDBRequest).result;
      if (_isNullish(result)) {
        completer.complete(null);
        return;
      }
      final cursor = result as web.IDBCursorWithValue;
      final row = _jsToRow(cursor.value);
      row['id'] = (cursor.key as JSNumber).toDartInt;
      completer.complete(PersistedSessionReplayEvent.fromDbRow(row));
    }.toJS;
    request.onerror = (web.Event event) {
      completer.completeError(StateError('Failed to fetch oldest event'));
    }.toJS;

    return completer.future;
  }

  @override
  Future<PersistedSessionReplayEvent?> fetchNewest() async {
    _checkState();

    final txn = _db!.transaction(_eventsStore.toJS, 'readonly');
    final store = txn.objectStore(_eventsStore);
    final request = store.openCursor(null, 'prev');

    final completer = Completer<PersistedSessionReplayEvent?>();
    request.onsuccess = (web.Event event) {
      final result = (event.target as web.IDBRequest).result;
      if (_isNullish(result)) {
        completer.complete(null);
        return;
      }
      final cursor = result as web.IDBCursorWithValue;
      final row = _jsToRow(cursor.value);
      row['id'] = (cursor.key as JSNumber).toDartInt;
      completer.complete(PersistedSessionReplayEvent.fromDbRow(row));
    }.toJS;
    request.onerror = (web.Event event) {
      completer.completeError(StateError('Failed to fetch newest event'));
    }.toJS;

    return completer.future;
  }

  @override
  Future<QueuedEventHeader?> fetchOldestHeader() => _fetchHeader('next');

  @override
  Future<QueuedEventHeader?> fetchNewestHeader() => _fetchHeader('prev');

  Future<QueuedEventHeader?> _fetchHeader(String direction) async {
    _checkState();

    final txn = _db!.transaction(_eventsStore.toJS, 'readonly');
    final index = txn.objectStore(_eventsStore).index(_eventHeaderIndex);
    final request = index.openKeyCursor(null, direction);
    final completer = Completer<QueuedEventHeader?>();

    request.onsuccess = (web.Event event) {
      final result = (event.target as web.IDBRequest).result;
      if (_isNullish(result)) {
        completer.complete(null);
        return;
      }

      final cursor = result as web.IDBCursor;
      final key = (cursor.key.dartify()! as List).cast<Object?>();
      completer.complete(
        QueuedEventHeader(
          id: _asInt(key[0]),
          sessionId: key[1] as String,
          distinctId: key[2] as String,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            _asInt(key[3]),
            isUtc: true,
          ),
        ),
      );
    }.toJS;
    request.onerror = (web.Event event) {
      completer.completeError(StateError('Failed to fetch event header'));
    }.toJS;

    return completer.future;
  }

  @override
  Future<List<PersistedSessionReplayEvent>> fetchBatch({
    required String sessionId,
    required String distinctId,
    required int maxBytes,
    required int maxCount,
  }) async {
    _checkState();

    final txn = _db!.transaction(_eventsStore.toJS, 'readonly');
    final store = txn.objectStore(_eventsStore);
    final index = store.index(_sessionIndex);
    final request = index.openCursor(sessionId.toJS);

    final batch = <PersistedSessionReplayEvent>[];
    int totalBytes = 0;

    final completer = Completer<List<PersistedSessionReplayEvent>>();

    request.onsuccess = (web.Event event) {
      final result = (event.target as web.IDBRequest).result;
      if (_isNullish(result)) {
        completer.complete(batch);
        return;
      }

      final cursor = result as web.IDBCursorWithValue;
      final row = _jsToRow(cursor.value);
      row['id'] = (cursor.primaryKey as JSNumber).toDartInt;

      final eventDistinctId = row['distinct_id'] as String;

      // Stop at distinctId boundary
      if (eventDistinctId != distinctId) {
        completer.complete(batch);
        return;
      }

      final dataSize = _asInt(row['data_size']);

      // Check size/count limits (always include at least one event)
      if (batch.isNotEmpty &&
          (totalBytes + dataSize > maxBytes || batch.length >= maxCount)) {
        completer.complete(batch);
        return;
      }

      batch.add(PersistedSessionReplayEvent.fromDbRow(row));
      totalBytes += dataSize;

      cursor.continue_();
    }.toJS;

    request.onerror = (web.Event event) {
      completer.completeError(StateError('Failed to fetch batch'));
    }.toJS;

    return completer.future;
  }

  @override
  Future<void> createSessionMetadata(Session session) async {
    _checkState();

    final txn = _db!.transaction(_metadataStore.toJS, 'readwrite');
    final store = txn.objectStore(_metadataStore);
    final getRequest = store.get(session.id.toJS);

    // Check-then-insert in a single transaction: the put() is issued inside
    // the get's onsuccess callback, before the event loop yields, so the
    // transaction stays alive.
    getRequest.onsuccess = (web.Event event) {
      final result = (event.target as web.IDBRequest).result;
      if (!_isNullish(result)) return; // Already exists

      final record = <String, dynamic>{
        'session_id': session.id,
        'last_sequence_number': -1,
        'session_start_time': session.startTime.millisecondsSinceEpoch,
        'owner_id': ownerId,
      };
      store.put(record.jsify()!);
    }.toJS;

    await _awaitTransaction(txn);
  }

  @override
  Future<Session?> getSessionMetadata(String sessionId) async {
    _checkState();

    final txn = _db!.transaction(_metadataStore.toJS, 'readonly');
    final store = txn.objectStore(_metadataStore);
    final request = store.get(sessionId.toJS);

    final result = await _awaitRequest(request);
    if (_isNullish(result)) return null;

    final map = result.dartify()! as Map;
    return Session(
      id: map['session_id'] as String,
      startTime: DateTime.fromMillisecondsSinceEpoch(
        _asInt(map['session_start_time']),
        isUtc: true,
      ),
      status: SessionStatus.ended,
    );
  }

  @override
  Future<void> remove(List<PersistedSessionReplayEvent> events) async {
    _checkState();
    if (events.isEmpty) return;

    final txn = _db!.transaction(
      [
        _eventsStore,
        _coordinationStore,
      ].map((store) => store.toJS).toList().toJS,
      'readwrite',
    );
    final store = txn.objectStore(_eventsStore);
    var remainingSize = _currentSizeBytes;
    _deleteEventsAndUpdateSizeInTransaction(
      events: events,
      eventsStore: store,
      coordinationStore: txn.objectStore(_coordinationStore),
      onComputed: (size) => remainingSize = size,
    );
    await _awaitTransaction(txn);
    _currentSizeBytes = remainingSize;
  }

  @override
  Future<void> removeAll() async {
    _checkState();

    final txn = _db!.transaction(
      [
        _eventsStore,
        _metadataStore,
        _coordinationStore,
      ].map((store) => store.toJS).toList().toJS,
      'readwrite',
    );
    txn.objectStore(_eventsStore).clear();
    txn.objectStore(_metadataStore).clear();
    txn.objectStore(_coordinationStore).put(_storageSizeRecord(0));
    await _awaitTransaction(txn);

    _currentSizeBytes = 0;
  }

  @override
  Future<int> getLastSequenceNumber(String sessionId) async {
    _checkState();

    final txn = _db!.transaction(_metadataStore.toJS, 'readonly');
    final store = txn.objectStore(_metadataStore);
    final request = store.get(sessionId.toJS);

    final result = await _awaitRequest(request);
    if (_isNullish(result)) return -1;

    final map = result.dartify()! as Map;
    return _asInt(map['last_sequence_number']);
  }

  @override
  Future<void> updateSequenceNumber(
    String sessionId,
    int sequenceNumber,
  ) async {
    _checkState();

    final txn = _db!.transaction(_metadataStore.toJS, 'readwrite');
    final store = txn.objectStore(_metadataStore);
    final getRequest = store.get(sessionId.toJS);

    // Read-modify-write in a single transaction: the put() is issued inside
    // the get's onsuccess callback before the event loop yields.
    bool found = false;

    getRequest.onsuccess = (web.Event event) {
      final result = (event.target as web.IDBRequest).result;
      if (_isNullish(result)) return;

      found = true;
      final map = (result.dartify()! as Map).cast<String, dynamic>();
      map['last_sequence_number'] = sequenceNumber;
      store.put(map.jsify()!);
    }.toJS;

    await _awaitTransaction(txn);

    if (!found) {
      throw StateError('Session metadata not found for session $sessionId');
    }
  }

  @override
  Future<bool> acquireUploadLease({
    required String ownerId,
    required Duration ttl,
  }) async {
    _checkState();

    final txn = _db!.transaction(_coordinationStore.toJS, 'readwrite');
    final store = txn.objectStore(_coordinationStore);
    final request = store.get(_uploadLeaseKey.toJS);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    var acquired = false;

    request.onsuccess = (web.Event event) {
      final result = (event.target as web.IDBRequest).result;
      Map<String, dynamic>? current;
      if (!_isNullish(result)) {
        current = (result.dartify()! as Map).cast<String, dynamic>();
      }

      final expiresAt = _asNullableInt(current?['expires_at']) ?? 0;
      final currentOwner = current?['owner_id'] as String?;
      if (currentOwner != ownerId && expiresAt > nowMs) return;

      acquired = true;
      store.put(
        <String, dynamic>{
          'name': _uploadLeaseKey,
          'owner_id': ownerId,
          'expires_at': nowMs + ttl.inMilliseconds,
        }.jsify()!,
      );
    }.toJS;

    await _awaitTransaction(txn);
    return acquired;
  }

  @override
  Future<void> releaseUploadLease({required String ownerId}) async {
    _checkState();

    final txn = _db!.transaction(_coordinationStore.toJS, 'readwrite');
    final store = txn.objectStore(_coordinationStore);
    final request = store.get(_uploadLeaseKey.toJS);

    request.onsuccess = (web.Event event) {
      final result = (event.target as web.IDBRequest).result;
      if (_isNullish(result)) return;
      final current = (result.dartify()! as Map).cast<String, dynamic>();
      if (current['owner_id'] == ownerId) {
        store.delete(_uploadLeaseKey.toJS);
      }
    }.toJS;

    await _awaitTransaction(txn);
  }

  @override
  Future<void> commitUploadedBatch({
    required List<PersistedSessionReplayEvent> events,
    required String sessionId,
    required int sequenceNumber,
  }) async {
    _checkState();
    if (events.isEmpty) return;

    final txn = _db!.transaction(
      [
        _eventsStore,
        _metadataStore,
        _coordinationStore,
      ].map((store) => store.toJS).toList().toJS,
      'readwrite',
    );
    final eventsStore = txn.objectStore(_eventsStore);
    final metadataStore = txn.objectStore(_metadataStore);
    final coordinationStore = txn.objectStore(_coordinationStore);
    final metadataRequest = metadataStore.get(sessionId.toJS);
    var remainingSize = _currentSizeBytes;

    metadataRequest.onsuccess = (web.Event event) {
      final result = (event.target as web.IDBRequest).result;
      if (_isNullish(result)) {
        txn.abort();
        return;
      }

      final metadata = (result.dartify()! as Map).cast<String, dynamic>();
      metadata['last_sequence_number'] = sequenceNumber;
      metadataStore.put(metadata.jsify()!);
    }.toJS;

    _deleteEventsAndUpdateSizeInTransaction(
      events: events,
      eventsStore: eventsStore,
      coordinationStore: coordinationStore,
      onComputed: (size) => remainingSize = size,
    );

    await _awaitTransaction(txn);
    _currentSizeBytes = remainingSize;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _db?.close();
    _db = null;
  }

  /// Remove events older than [cutoff] and unreferenced session metadata from
  /// the same period.
  ///
  /// Event deletion, metadata cleanup, and quota reconstruction share one
  /// transaction. A key-only timestamp cursor avoids loading expired JPEGs.
  Future<RetentionCleanupResult> pruneExpiredData(DateTime cutoff) async {
    _checkState();

    final txn = _db!.transaction(
      [
        _eventsStore,
        _metadataStore,
        _coordinationStore,
      ].map((store) => store.toJS).toList().toJS,
      'readwrite',
    );
    final eventsStore = txn.objectStore(_eventsStore);
    final metadataStore = txn.objectStore(_metadataStore);
    final coordinationStore = txn.objectStore(_coordinationStore);
    final cutoffMs = cutoff.toUtc().millisecondsSinceEpoch;
    var removedEvents = 0;
    var removedSessions = 0;
    var remainingSize = _currentSizeBytes;

    final expiredEvents = eventsStore
        .index(_eventTimestampIndex)
        .openKeyCursor(web.IDBKeyRange.upperBound(cutoffMs.toJS));
    expiredEvents.onsuccess = (web.Event event) {
      final result = (event.target as web.IDBRequest).result;
      if (!_isNullish(result)) {
        final cursor = result as web.IDBCursor;
        eventsStore.delete(cursor.primaryKey);
        removedEvents++;
        cursor.continue_();
        return;
      }

      _recalculateSizeInTransaction(
        eventsStore: eventsStore,
        coordinationStore: coordinationStore,
        onComputed: (size) => remainingSize = size,
      );
      _pruneUnreferencedMetadataInTransaction(
        cutoffMs: cutoffMs,
        eventsStore: eventsStore,
        metadataStore: metadataStore,
        onRemoved: () => removedSessions++,
      );
    }.toJS;

    await _awaitTransaction(txn);
    _currentSizeBytes = remainingSize;
    return RetentionCleanupResult(
      removedEvents: removedEvents,
      removedSessions: removedSessions,
    );
  }

  // -- Web session resume/expiry methods (not on EventQueue interface) --

  /// Persist session expiry timestamps alongside metadata.
  ///
  /// Updates (or creates) the `idle_expires` and `max_expires` fields
  /// on the session_metadata record. IndexedDB is schemaless for value
  /// fields so no version bump is needed.
  Future<void> updateSessionExpiry({
    required String sessionId,
    required int idleExpiresMs,
    required int maxExpiresMs,
  }) async {
    _checkState();

    final txn = _db!.transaction(_metadataStore.toJS, 'readwrite');
    final store = txn.objectStore(_metadataStore);
    final getRequest = store.get(sessionId.toJS);

    // Read-modify-write in a single transaction.
    getRequest.onsuccess = (web.Event event) {
      final result = (event.target as web.IDBRequest).result;
      if (_isNullish(result)) return;

      final map = (result.dartify()! as Map).cast<String, dynamic>();
      map['idle_expires'] = idleExpiresMs;
      map['max_expires'] = maxExpiresMs;
      map['owner_id'] = ownerId;
      store.put(map.jsify()!);
    }.toJS;

    await _awaitTransaction(txn);
  }

  /// Read the latest session's metadata including expiry info.
  ///
  /// Returns a map with keys: `session_id`, `session_start_time`,
  /// `last_sequence_number`, and optionally `idle_expires`, `max_expires`.
  /// Returns null if no sessions exist.
  ///
  /// Uses the descending session-start index and stops at the first record
  /// owned by this tab (or a legacy unowned record when allowed).
  Future<Map<String, dynamic>?> getLatestSessionMetadata({
    String? ownedBy,
    bool includeUnowned = true,
  }) async {
    _checkState();

    final txn = _db!.transaction(_metadataStore.toJS, 'readonly');
    final store = txn.objectStore(_metadataStore);
    final request = store.index(_metadataStartIndex).openCursor(null, 'prev');

    final completer = Completer<Map<String, dynamic>?>();

    request.onsuccess = (web.Event event) {
      final result = (event.target as web.IDBRequest).result;
      if (_isNullish(result)) {
        completer.complete(null);
        return;
      }

      final cursor = result as web.IDBCursorWithValue;
      final map = (cursor.value.dartify()! as Map).cast<String, dynamic>();
      for (final key in const [
        'session_start_time',
        'last_sequence_number',
        'idle_expires',
        'max_expires',
      ]) {
        final value = map[key];
        if (value != null) map[key] = _asInt(value);
      }
      final recordOwner = map['owner_id'] as String?;
      if (ownedBy != null &&
          recordOwner != ownedBy &&
          !(includeUnowned && recordOwner == null)) {
        cursor.continue_();
        return;
      }
      completer.complete(map);
    }.toJS;

    request.onerror = (web.Event event) {
      completer.completeError(
        StateError('Failed to read latest session metadata'),
      );
    }.toJS;

    return completer.future;
  }

  /// Atomically adopts legacy unowned metadata, or confirms ownership of a
  /// session already associated with this browser tab.
  Future<bool> claimSessionOwnership(String sessionId) async {
    _checkState();
    final txn = _db!.transaction(_metadataStore.toJS, 'readwrite');
    final store = txn.objectStore(_metadataStore);
    final request = store.get(sessionId.toJS);
    var claimed = false;

    request.onsuccess = (web.Event event) {
      final result = (event.target as web.IDBRequest).result;
      if (_isNullish(result)) return;
      final map = (result.dartify()! as Map).cast<String, dynamic>();
      final currentOwner = map['owner_id'] as String?;
      if (currentOwner != null && currentOwner != ownerId) return;
      map['owner_id'] = ownerId;
      store.put(map.jsify()!);
      claimed = true;
    }.toJS;

    await _awaitTransaction(txn);
    return claimed;
  }

  // -- Helpers --

  void _checkState() {
    if (_disposed) throw StateError('EventQueue has been disposed');
    if (_db == null) throw StateError('EventQueue not initialized');
  }

  /// Rebuild the shared size record while holding a transaction over both the
  /// event and coordination stores. This also migrates databases created
  /// before the size record existed without a schema-version change.
  Future<int> _synchronizeTotalSize() async {
    final txn = _db!.transaction(
      [
        _eventsStore,
        _coordinationStore,
      ].map((store) => store.toJS).toList().toJS,
      'readwrite',
    );
    var total = 0;
    _recalculateSizeInTransaction(
      eventsStore: txn.objectStore(_eventsStore),
      coordinationStore: txn.objectStore(_coordinationStore),
      onComputed: (size) => total = size,
    );
    await _awaitTransaction(txn);
    return total;
  }

  void _recalculateSizeInTransaction({
    required web.IDBObjectStore eventsStore,
    required web.IDBObjectStore coordinationStore,
    required void Function(int) onComputed,
  }) {
    var total = 0;
    // A key cursor over the size index avoids cloning every stored JPEG into
    // the UI isolate while rebuilding quota state on startup.
    final request = eventsStore.index(_eventSizeIndex).openKeyCursor();
    request.onsuccess = (web.Event event) {
      final result = (event.target as web.IDBRequest).result;
      if (_isNullish(result)) {
        coordinationStore.put(_storageSizeRecord(total));
        onComputed(total);
        return;
      }
      final cursor = result as web.IDBCursor;
      total += (cursor.key as JSNumber).toDartInt;
      cursor.continue_();
    }.toJS;
  }

  void _pruneUnreferencedMetadataInTransaction({
    required int cutoffMs,
    required web.IDBObjectStore eventsStore,
    required web.IDBObjectStore metadataStore,
    required void Function() onRemoved,
  }) {
    final expiredSessionIds = <String>[];
    final request = metadataStore
        .index(_metadataStartIndex)
        .openKeyCursor(web.IDBKeyRange.upperBound(cutoffMs.toJS));
    request.onsuccess = (web.Event event) {
      final result = (event.target as web.IDBRequest).result;
      if (!_isNullish(result)) {
        final cursor = result as web.IDBCursor;
        expiredSessionIds.add((cursor.primaryKey as JSString).toDart);
        cursor.continue_();
        return;
      }

      final sessionIndex = eventsStore.index(_sessionIndex);
      for (final sessionId in expiredSessionIds) {
        final eventKeyRequest = sessionIndex.getKey(sessionId.toJS);
        eventKeyRequest.onsuccess = (web.Event event) {
          final eventKey = (event.target as web.IDBRequest).result;
          if (_isNullish(eventKey)) {
            metadataStore.delete(sessionId.toJS);
            onRemoved();
          }
        }.toJS;
      }
    }.toJS;
  }

  /// Delete only records that still exist and decrement the shared size by
  /// their stored sizes. Reading before deleting keeps repeated deletion
  /// idempotent without scanning the full event store after every upload.
  void _deleteEventsAndUpdateSizeInTransaction({
    required List<PersistedSessionReplayEvent> events,
    required web.IDBObjectStore eventsStore,
    required web.IDBObjectStore coordinationStore,
    required void Function(int) onComputed,
  }) {
    var currentSize = _currentSizeBytes;
    var removedBytes = 0;
    var pendingEvents = events.length;
    var sizeReady = false;

    void commitSizeIfReady() {
      if (!sizeReady || pendingEvents != 0) return;
      final computedSize = currentSize - removedBytes;
      final remainingSize = computedSize < 0 ? 0 : computedSize;
      coordinationStore.put(_storageSizeRecord(remainingSize));
      onComputed(remainingSize);
    }

    final sizeRequest = coordinationStore.get(_storageSizeKey.toJS);
    sizeRequest.onsuccess = (web.Event event) {
      final result = (event.target as web.IDBRequest).result;
      if (!_isNullish(result)) {
        final record = (result.dartify()! as Map).cast<String, dynamic>();
        currentSize = _asInt(record['bytes']);
      }
      sizeReady = true;
      commitSizeIfReady();
    }.toJS;

    for (final replayEvent in events) {
      // getKey() verifies existence without structured-cloning the screenshot
      // payload back onto the main isolate solely to delete it.
      final request = eventsStore.getKey(replayEvent.id.toJS);
      request.onsuccess = (web.Event event) {
        final result = (event.target as web.IDBRequest).result;
        if (!_isNullish(result)) {
          removedBytes += replayEvent.dataSize;
          eventsStore.delete(replayEvent.id.toJS);
        }
        pendingEvents--;
        commitSizeIfReady();
      }.toJS;
    }
  }

  JSAny _storageSizeRecord(int bytes) =>
      <String, dynamic>{'name': _storageSizeKey, 'bytes': bytes}.jsify()!;

  /// Convert a Dart row map to a JS object for IndexedDB storage.
  /// jsify() handles Uint8List → JSUint8Array for structured clone.
  JSAny _dartMapToJs(Map<String, dynamic> row) => row.jsify()!;

  /// Convert a JS object from IndexedDB back to a Dart row map.
  /// dartify() converts JS typed arrays back to Dart typed data.
  Map<String, dynamic> _jsToRow(JSAny? jsValue) {
    final map = (jsValue.dartify()! as Map).cast<String, dynamic>();
    for (final key in const ['timestamp', 'type', 'data_size']) {
      map[key] = _asInt(map[key]);
    }
    // dartify may return ByteBuffer or Uint8List depending on how IDB stored it
    final binary = map['payload_binary'];
    if (binary is ByteBuffer) {
      map['payload_binary'] = binary.asUint8List();
    }
    return map;
  }

  Future<JSAny?> _awaitRequest(web.IDBRequest request) {
    final completer = Completer<JSAny?>();
    request.onsuccess = (web.Event event) {
      completer.complete((event.target as web.IDBRequest).result);
    }.toJS;
    request.onerror = (web.Event event) {
      completer.completeError(
        StateError('IDB request failed: ${request.error}'),
      );
    }.toJS;
    return completer.future;
  }

  Future<void> _awaitTransaction(web.IDBTransaction txn) {
    final completer = Completer<void>();
    txn.oncomplete = (web.Event event) {
      if (!completer.isCompleted) completer.complete();
    }.toJS;
    txn.onerror = (web.Event event) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('IDB transaction failed: ${txn.error}'),
        );
      }
    }.toJS;
    txn.onabort = (web.Event event) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('IDB transaction aborted: ${txn.error}'),
        );
      }
    }.toJS;
    return completer.future;
  }
}

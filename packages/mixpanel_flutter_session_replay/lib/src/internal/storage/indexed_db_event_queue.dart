import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:uuid/uuid.dart';

import 'event_queue_interface.dart';
import '../../models/session_event.dart';
import '../../models/session.dart';
import '../logger.dart';
import '../session/recording_limits.dart';
import 'upload_lease.dart';

const _eventsStore = 'events';
const _metadataStore = 'session_metadata';
const _sessionIndex = 'by_session';
const _eventSizeIndex = 'by_size';
const _eventHeaderIndex = 'by_id_header';
const _eventTimestampIndex = 'by_timestamp';
const _metadataStartIndex = 'by_start_time';
const _coordinationStore = 'coordination';
const _uploadLeaseKeyPrefix = 'upload_lease:';
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

  /// The tab owner id doubles as the upload lease owner so a reload can
  /// resume its own lease instead of waiting out the TTL.
  @override
  String get uploadLeaseOwnerId => ownerId;
  web.IDBDatabase? _db;
  bool _disposed = false;
  bool _initialized = false;
  Future<void>? _reopening;
  DateTime? _reopenRetryAfter;

  static const _schemaVersion = 5;
  static const _reopenRetryInterval = Duration(seconds: 30);

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
    _attach(await _openDatabase());

    // Synchronize a transactional size record used by every open tab. A
    // process-local counter alone can allow concurrent tabs to exceed quota.
    _currentSizeBytes = await _synchronizeTotalSize();
    _initialized = true;
  }

  /// Opens the database, creating or upgrading its schema as needed.
  Future<web.IDBDatabase> _openDatabase() async {
    final completer = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(_dbName, _schemaVersion);
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
      _logger.debug('IndexedDB opened: $_dbName');
      completer.complete(openedDb);
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

    return completer.future;
  }

  /// Adopts [db] as the live connection and watches for it being closed.
  void _attach(web.IDBDatabase db) {
    _db = db;
    // Another tab is upgrading or deleting the database. Close so that tab
    // is not blocked; the next operation reopens the connection.
    db.onversionchange = (web.Event event) {
      _logger.info('IndexedDB version changed; closing stale connection');
      _dropConnection(db);
    }.toJS;
    // The browser closed the connection abnormally, for example after the
    // storage was cleared or the backing store failed.
    db.onclose = (web.Event event) {
      _logger.warning('IndexedDB connection closed by the browser');
      _dropConnection(db);
    }.toJS;
  }

  void _dropConnection(web.IDBDatabase db) {
    if (!identical(_db, db)) return;
    _db = null;
    try {
      db.close();
    } catch (_) {}
  }

  /// Makes sure a live connection exists before an operation starts.
  ///
  /// Like mixpanel-js, a closed connection is reopened lazily by the next
  /// operation instead of leaving the queue unusable until the page reloads.
  /// Failed reopens are retried at most every [_reopenRetryInterval]: once a
  /// newer schema is installed by another tab, opening this version fails
  /// until the page reloads with the newer SDK.
  Future<void> _ensureOpen() async {
    _checkState();
    if (_db != null) return;
    final retryAfter = _reopenRetryAfter;
    if (retryAfter != null && DateTime.now().isBefore(retryAfter)) {
      throw StateError('IndexedDB connection is closed: $_dbName');
    }
    await (_reopening ??= _reopen().whenComplete(() => _reopening = null));
    if (_disposed) throw StateError('EventQueue has been disposed');
  }

  Future<void> _reopen() async {
    try {
      final db = await _openDatabase();
      if (_disposed) {
        db.close();
        return;
      }
      _attach(db);
      _currentSizeBytes = await _synchronizeTotalSize();
      _reopenRetryAfter = null;
      _logger.info('IndexedDB connection reopened: $_dbName');
    } catch (error) {
      _reopenRetryAfter = DateTime.now().add(_reopenRetryInterval);
      _logger.warning('Failed to reopen IndexedDB: $error');
      rethrow;
    }
  }

  /// Starts a transaction on the live connection.
  ///
  /// The browser can close a connection without an event reaching Dart
  /// first. A failure here drops the connection so the next operation
  /// reopens it, matching mixpanel-js's retry on `InvalidStateError`.
  web.IDBTransaction _transaction(JSAny storeNames, String mode) {
    // A versionchange or close event can land between _ensureOpen() and here.
    final db = _db;
    if (db == null) {
      throw StateError('IndexedDB connection is closed: $_dbName');
    }
    try {
      return db.transaction(storeNames, mode);
    } catch (_) {
      _dropConnection(db);
      rethrow;
    }
  }

  @override
  Future<void> add(SessionReplayEvent event) async {
    await _ensureOpen();

    final row = event.toDbRow();
    final eventSize = row['data_size'] as int;

    final quotaBytes = quotaMB * 1024 * 1024;
    final txn = _transaction(
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

  /// Sessions whose events this tab must leave alone: recorded by another tab
  /// and not yet expired.
  ///
  /// Mirrors mixpanel-js, where a tab uploads only its own replay plus the
  /// leftovers of expired ones. Orphaned events with no metadata have no live
  /// owner and are always eligible. A record with no deadlines yet is treated
  /// as live until it is older than the longest possible recording.
  Future<Set<String>> _foreignLiveSessionIds() async {
    final txn = _transaction(_metadataStore.toJS, 'readonly');
    final result = await _awaitRequest(
      txn.objectStore(_metadataStore).getAll(),
    );
    final blocked = <String>{};
    if (_isNullish(result)) return blocked;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final record in (result.dartify()! as List)) {
      final map = (record as Map).cast<String, dynamic>();
      if (map['owner_id'] == ownerId) continue;
      if (_isSessionLive(map, nowMs)) blocked.add(map['session_id'] as String);
    }
    return blocked;
  }

  static bool _isSessionLive(Map<String, dynamic> metadata, int nowMs) {
    final deadlines = [
      _asNullableInt(metadata['idle_expires']),
      _asNullableInt(metadata['max_expires']),
      _asNullableInt(metadata['background_expires']),
    ].nonNulls.toList();
    if (deadlines.isEmpty) {
      final startMs = _asNullableInt(metadata['session_start_time']) ?? 0;
      return nowMs - startMs < maxRecordingDuration.inMilliseconds;
    }
    return deadlines.every((deadline) => nowMs < deadline);
  }

  @override
  Future<PersistedSessionReplayEvent?> fetchOldest() async {
    await _ensureOpen();
    final blocked = await _foreignLiveSessionIds();

    final txn = _transaction(_eventsStore.toJS, 'readonly');
    final store = txn.objectStore(_eventsStore);
    final request = store.openCursor();

    return _completeFromRequest(txn, request, 'Failed to fetch oldest event', (
      result,
      completer,
    ) {
      if (_isNullish(result)) {
        completer.complete(null);
        return;
      }
      final cursor = result as web.IDBCursorWithValue;
      final row = _jsToRow(cursor.value);
      if (blocked.contains(row['session_id'])) {
        cursor.continue_();
        return;
      }
      row['id'] = (cursor.key as JSNumber).toDartInt;
      completer.complete(PersistedSessionReplayEvent.fromDbRow(row));
    });
  }

  @override
  Future<PersistedSessionReplayEvent?> fetchNewest() async {
    await _ensureOpen();
    final blocked = await _foreignLiveSessionIds();

    final txn = _transaction(_eventsStore.toJS, 'readonly');
    final store = txn.objectStore(_eventsStore);
    final request = store.openCursor(null, 'prev');

    return _completeFromRequest(txn, request, 'Failed to fetch newest event', (
      result,
      completer,
    ) {
      if (_isNullish(result)) {
        completer.complete(null);
        return;
      }
      final cursor = result as web.IDBCursorWithValue;
      final row = _jsToRow(cursor.value);
      if (blocked.contains(row['session_id'])) {
        cursor.continue_();
        return;
      }
      row['id'] = (cursor.key as JSNumber).toDartInt;
      completer.complete(PersistedSessionReplayEvent.fromDbRow(row));
    });
  }

  @override
  Future<QueuedEventHeader?> fetchOldestHeader() => _fetchHeader('next');

  @override
  Future<QueuedEventHeader?> fetchNewestHeader() => _fetchHeader('prev');

  Future<QueuedEventHeader?> _fetchHeader(String direction) async {
    await _ensureOpen();
    final blocked = await _foreignLiveSessionIds();

    final txn = _transaction(_eventsStore.toJS, 'readonly');
    final index = txn.objectStore(_eventsStore).index(_eventHeaderIndex);
    final request = index.openKeyCursor(null, direction);

    return _completeFromRequest(txn, request, 'Failed to fetch event header', (
      result,
      completer,
    ) {
      if (_isNullish(result)) {
        completer.complete(null);
        return;
      }

      final cursor = result as web.IDBCursor;
      final key = (cursor.key.dartify()! as List).cast<Object?>();
      if (blocked.contains(key[1])) {
        cursor.continue_();
        return;
      }
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
    });
  }

  @override
  Future<List<PersistedSessionReplayEvent>> fetchBatch({
    required String sessionId,
    required String distinctId,
    required int maxBytes,
    required int maxCount,
  }) async {
    await _ensureOpen();

    final txn = _transaction(_eventsStore.toJS, 'readonly');
    final store = txn.objectStore(_eventsStore);
    final index = store.index(_sessionIndex);
    final request = index.openCursor(sessionId.toJS);

    final batch = <PersistedSessionReplayEvent>[];
    int totalBytes = 0;

    return _completeFromRequest(txn, request, 'Failed to fetch batch', (
      result,
      completer,
    ) {
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
    });
  }

  @override
  Future<void> createSessionMetadata(Session session) async {
    await _ensureOpen();

    final txn = _transaction(_metadataStore.toJS, 'readwrite');
    final store = txn.objectStore(_metadataStore);
    final getRequest = store.get(session.id.toJS);

    // Check-then-insert in a single transaction: the put() is issued inside
    // the get's onsuccess callback, before the event loop yields, so the
    // transaction stays alive.
    getRequest.onsuccess = (web.Event event) {
      final result = (event.target as web.IDBRequest).result;
      if (!_isNullish(result)) return; // Already exists

      // Only a live session belongs to this tab. Metadata rebuilt by the
      // uploader for an orphaned backlog is marked ended: it stays unowned and
      // carries already-passed deadlines, like mixpanel-js setting maxExpires
      // to zero, so any tab may upload its events but none can resume it.
      final live = session.status == SessionStatus.active;
      final record = <String, dynamic>{
        'session_id': session.id,
        'last_sequence_number': -1,
        'session_start_time': session.startTime.millisecondsSinceEpoch,
        'owner_id': live ? ownerId : null,
        if (!live) 'idle_expires': 0,
        if (!live) 'max_expires': 0,
      };
      store.put(record.jsify()!);
    }.toJS;

    await _awaitTransaction(txn);
  }

  @override
  Future<Session?> getSessionMetadata(String sessionId) async {
    await _ensureOpen();

    final txn = _transaction(_metadataStore.toJS, 'readonly');
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
    await _ensureOpen();
    if (events.isEmpty) return;

    final txn = _transaction(
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
    await _ensureOpen();

    final txn = _transaction(
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
    await _ensureOpen();

    final txn = _transaction(_metadataStore.toJS, 'readonly');
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
    await _ensureOpen();

    final txn = _transaction(_metadataStore.toJS, 'readwrite');
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

  static String _leaseKey(String sessionId) =>
      '$_uploadLeaseKeyPrefix$sessionId';

  @override
  Future<bool> acquireUploadLease({
    required String ownerId,
    required String sessionId,
    required Duration ttl,
  }) async {
    await _ensureOpen();

    final txn = _transaction(_coordinationStore.toJS, 'readwrite');
    final store = txn.objectStore(_coordinationStore);
    final leaseKey = _leaseKey(sessionId);
    final request = store.get(leaseKey.toJS);
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
          'name': leaseKey,
          'owner_id': ownerId,
          'expires_at': nowMs + ttl.inMilliseconds,
        }.jsify()!,
      );
    }.toJS;

    await _awaitTransaction(txn);
    return acquired;
  }

  @override
  Future<void> releaseUploadLease({
    required String ownerId,
    required String sessionId,
  }) async {
    await _ensureOpen();

    final txn = _transaction(_coordinationStore.toJS, 'readwrite');
    final store = txn.objectStore(_coordinationStore);
    final leaseKey = _leaseKey(sessionId);
    final request = store.get(leaseKey.toJS);

    request.onsuccess = (web.Event event) {
      final result = (event.target as web.IDBRequest).result;
      if (_isNullish(result)) return;
      final current = (result.dartify()! as Map).cast<String, dynamic>();
      if (current['owner_id'] == ownerId) {
        store.delete(leaseKey.toJS);
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
    await _ensureOpen();
    if (events.isEmpty) return;

    final txn = _transaction(
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
    var remainingSize = _currentSizeBytes;

    // Issued first so a lost lease aborts before any delete is queued. A tab
    // frozen past its lease TTL can resume with a batch another tab already
    // uploaded; committing would advance the sequence past a number that tab
    // may still be about to use.
    final leaseRequest = coordinationStore.get(_leaseKey(sessionId).toJS);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    var leaseLost = false;
    leaseRequest.onsuccess = (web.Event event) {
      final result = (event.target as web.IDBRequest).result;
      if (_isNullish(result)) return;
      final lease = (result.dartify()! as Map).cast<String, dynamic>();
      final owner = lease['owner_id'] as String?;
      final expiresAt = _asNullableInt(lease['expires_at']) ?? 0;
      if (owner != null && owner != ownerId && expiresAt > nowMs) {
        leaseLost = true;
        txn.abort();
      }
    }.toJS;

    final metadataRequest = metadataStore.get(sessionId.toJS);
    metadataRequest.onsuccess = (web.Event event) {
      final result = (event.target as web.IDBRequest).result;
      if (_isNullish(result)) {
        txn.abort();
        return;
      }

      final metadata = (result.dartify()! as Map).cast<String, dynamic>();
      // The upload lease can expire while a frozen tab's request is in
      // flight, letting another tab upload and advance the sequence. Never
      // move it backwards, or the next batch would reuse a sent number.
      final previous = _asNullableInt(metadata['last_sequence_number']) ?? -1;
      if (sequenceNumber > previous) {
        metadata['last_sequence_number'] = sequenceNumber;
        metadataStore.put(metadata.jsify()!);
      }
    }.toJS;

    _deleteEventsAndUpdateSizeInTransaction(
      events: events,
      eventsStore: eventsStore,
      coordinationStore: coordinationStore,
      onComputed: (size) => remainingSize = size,
    );

    try {
      await _awaitTransaction(txn);
    } on StateError {
      if (leaseLost) {
        throw UploadLeaseLostException(
          'Upload lease for $_dbName is held by another tab; batch left queued',
        );
      }
      rethrow;
    }
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
    await _ensureOpen();

    final txn = _transaction(
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
  /// and nullable `background_expires` on the session_metadata record.
  /// IndexedDB is schemaless for value
  /// fields so no version bump is needed.
  Future<void> updateSessionExpiry({
    required String sessionId,
    required int idleExpiresMs,
    required int maxExpiresMs,
    int? backgroundExpiresMs,
  }) async {
    await _ensureOpen();

    final txn = _transaction(_metadataStore.toJS, 'readwrite');
    final store = txn.objectStore(_metadataStore);
    final getRequest = store.get(sessionId.toJS);

    // Read-modify-write in a single transaction.
    getRequest.onsuccess = (web.Event event) {
      final result = (event.target as web.IDBRequest).result;
      if (_isNullish(result)) return;

      final map = (result.dartify()! as Map).cast<String, dynamic>();
      map['idle_expires'] = idleExpiresMs;
      map['max_expires'] = maxExpiresMs;
      // Null clears the paused deadline when the page returns.
      map['background_expires'] = backgroundExpiresMs;
      // Adopt a legacy unowned record; never take one from another tab.
      map['owner_id'] ??= ownerId;
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
  /// owned by [ownedBy], or the first record of any owner when null.
  Future<Map<String, dynamic>?> getLatestSessionMetadata({
    String? ownedBy,
  }) async {
    await _ensureOpen();

    final txn = _transaction(_metadataStore.toJS, 'readonly');
    final store = txn.objectStore(_metadataStore);
    final request = store.index(_metadataStartIndex).openCursor(null, 'prev');

    return _completeFromRequest(
      txn,
      request,
      'Failed to read latest session metadata',
      (result, completer) {
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
          'background_expires',
        ]) {
          final value = map[key];
          if (value != null) map[key] = _asInt(value);
        }
        if (ownedBy != null && map['owner_id'] != ownedBy) {
          cursor.continue_();
          return;
        }
        completer.complete(map);
      },
    );
  }

  // -- Helpers --

  void _checkState() {
    if (_disposed) throw StateError('EventQueue has been disposed');
    if (!_initialized) throw StateError('EventQueue not initialized');
  }

  /// Rebuild the shared size record while holding a transaction over both the
  /// event and coordination stores. This also migrates databases created
  /// before the size record existed without a schema-version change.
  Future<int> _synchronizeTotalSize() async {
    final txn = _transaction(
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

  /// Completes a read whose result is produced inside the request's `success`
  /// callback rather than at transaction completion.
  ///
  /// A Dart exception thrown from that callback (for example a stored row this
  /// SDK version cannot parse) settles the request without an `error` event,
  /// and the browser then aborts the transaction silently. Without listening to
  /// the transaction's abort and error events the awaiting caller would never
  /// complete, and an upload that hit the row would stay "in flight" for the
  /// rest of the page's lifetime. [onSuccess] may be invoked once per cursor
  /// step; it completes [completer] when the read is done.
  Future<T> _completeFromRequest<T>(
    web.IDBTransaction txn,
    web.IDBRequest request,
    String failureMessage,
    void Function(JSAny? result, Completer<T> completer) onSuccess,
  ) {
    final completer = Completer<T>();
    void fail(Object error, [StackTrace? stackTrace]) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    }

    request.onsuccess = (web.Event event) {
      if (completer.isCompleted) return;
      try {
        onSuccess((event.target as web.IDBRequest).result, completer);
      } catch (error, stackTrace) {
        fail(error, stackTrace);
        try {
          txn.abort();
        } catch (_) {
          // The transaction may already have finished.
        }
      }
    }.toJS;
    request.onerror = (web.Event event) {
      fail(StateError('$failureMessage: ${request.error}'));
    }.toJS;
    txn.onabort = (web.Event event) {
      fail(StateError('$failureMessage: transaction aborted'));
    }.toJS;
    txn.onerror = (web.Event event) {
      fail(StateError('$failureMessage: ${txn.error}'));
    }.toJS;
    return completer.future;
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

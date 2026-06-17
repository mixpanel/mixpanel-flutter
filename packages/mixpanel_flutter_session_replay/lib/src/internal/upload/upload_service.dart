import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';

import '../endpoints.dart';
import '../storage/event_queue_interface.dart';
import 'payload_serializer.dart';
import '../settings/settings_service.dart';
import '../logger.dart';
import '../../models/results.dart';

/// Result of an upload attempt
enum UploadResult { success, networkError, serverError, quotaExceeded, backoff }

/// Service for uploading session replay events to Mixpanel
///
/// This service handles batching, network connectivity checks, retry logic,
/// and uses injected strategies for payload serialization.
class UploadService {
  /// Event queue for retrieving events
  final EventQueue eventQueue;

  /// Payload serializer (platform-specific)
  final PayloadSerializer payloadSerializer;

  /// Whether to only upload on WiFi
  final bool wifiOnly;

  /// Flush interval, resolved at construction time.
  ///
  /// Resolution rules:
  /// - Zero or negative input: stored as [Duration.zero] (auto-flush disabled)
  /// - Greater than zero but less than 1 second: stored as 1 second
  /// - 1 second or greater: stored as-is
  final Duration flushInterval;

  /// Logger instance
  final MixpanelLogger _logger;

  /// Connectivity monitor
  final Connectivity _connectivity;

  /// HTTP client
  final http.Client _httpClient;

  /// Timer for automatic flushing
  Timer? _flushTimer;

  /// Consecutive failure count for exponential backoff
  int _consecutiveFailures = 0;

  /// Time when requests are allowed again (for backoff)
  DateTime? _requestAllowedAfterTime;

  /// Mutex to ensure serial flush execution (prevents concurrent flushes)
  bool _isFlushing = false;

  /// Completer for coordinating concurrent flush calls
  Completer<FlushResult>? _flushCompleter;

  /// Cutoff timestamp for current flush operation (dynamically updated by concurrent calls)
  DateTime? _flushCutoffTimestamp;

  /// Callback to get the current remote enablement state.
  /// Flush operations are only allowed when state is [RemoteEnablementState.enabled].
  final RemoteEnablementState Function() getRemoteEnablementState;

  /// Whether this service has been disposed
  bool _isDisposed = false;

  /// Full `/record` endpoint, derived from the configured base URL.
  final String _endpoint;

  /// Minimum backoff delay (60 seconds)
  static const Duration _minBackoff = Duration(seconds: 60);

  /// Maximum backoff delay (10 minutes)
  static const Duration _maxBackoff = Duration(minutes: 10);

  /// Failures before backoff kicks in
  static const int _failuresBeforeBackoff = 2;

  /// Default maximum payload size per batch (5MB)
  static const int defaultMaxPayloadBytes = 5 * 1024 * 1024;

  /// Default maximum events per batch (safety limit to prevent pathological cases)
  static const int defaultMaxEventsPerBatch = 100;

  /// Maximum payload size per batch
  final int maxPayloadBytes;

  /// Maximum events per batch
  final int maxEventsPerBatch;

  UploadService({
    required this.eventQueue,
    required this.payloadSerializer,
    required this.wifiOnly,
    required this.getRemoteEnablementState,
    required Duration flushInterval,
    required MixpanelLogger logger,
    this.maxPayloadBytes = defaultMaxPayloadBytes,
    this.maxEventsPerBatch = defaultMaxEventsPerBatch,
    http.Client? httpClient,
    Connectivity? connectivity,
    String serverUrl = EndPoints.defaultBaseUrl,
  }) : flushInterval = flushInterval <= Duration.zero
           ? Duration.zero
           : flushInterval < const Duration(seconds: 1)
           ? const Duration(seconds: 1)
           : flushInterval,
       _logger = logger,
       _httpClient = httpClient ?? http.Client(),
       _connectivity = connectivity ?? Connectivity(),
       _endpoint = EndPoints.record(serverUrl);

  /// Start automatic flushing on an interval
  ///
  /// If [flushInterval] is [Duration.zero] (disabled), this is a no-op.
  void startAutoFlush() {
    if (flushInterval == Duration.zero) {
      _logger.info('Auto-flush disabled (flushInterval is zero or negative)');
      return;
    }

    if (_flushTimer?.isActive ?? false) {
      _logger.debug('Auto-flush already running, ignoring start');
      return;
    }

    _flushTimer = Timer.periodic(flushInterval, (_) {
      // Fire and forget - don't block timer callback
      // Use flushOneBatch for periodic uploads (not full queue drain)
      flushOneBatch().catchError((e) {
        _logger.error('Flush error: $e');
      });
    });
    _logger.info('Auto-flush started (interval: $flushInterval)');
  }

  /// Stop automatic flushing
  void stopAutoFlush() {
    if (_flushTimer?.isActive ?? false) {
      _flushTimer?.cancel();
      _logger.info('Auto-flush stopped');
    }
  }

  /// Flush one batch of events (used by periodic timer)
  ///
  /// Uploads a single batch (up to 5MB or 100 events).
  /// If events are falling behind (oldest event is older than flush interval),
  /// schedules another immediate flush to catch up.
  Future<void> flushOneBatch() async {
    _logger.debug(
      'flushOneBatch called (timer active: ${_flushTimer?.isActive})',
    );

    // Check remote settings state
    final remoteState = getRemoteEnablementState();
    if (remoteState != RemoteEnablementState.enabled) {
      _logger.debug('Flush skipped - remote settings state: $remoteState');
      return;
    }

    // Prevent concurrent flushes
    if (_isFlushing) {
      _logger.debug('Already flushing, skipping');
      return;
    }

    _isFlushing = true;

    try {
      // Check backoff
      if (_isInBackoff()) {
        _logger.debug('In backoff period, skipping flush');
        return;
      }

      // Check connectivity
      if (wifiOnly && !(await _isWiFiConnected())) {
        _logger.debug('Not on WiFi, skipping flush');
        return;
      }

      // Upload ONE batch only (for periodic timer)
      final result = await _uploadBatch();

      if (result == UploadResult.success) {
        _consecutiveFailures = 0;
        _requestAllowedAfterTime = null;

        // Check if we're falling behind - check oldest event across ALL sessions
        final oldestEvent = await eventQueue.fetchOldest();
        if (oldestEvent != null) {
          final age = clock.now().difference(oldestEvent.timestamp);
          _logger.debug(
            'Oldest event age: ${age.inSeconds}s (threshold: ${flushInterval.inSeconds}s)',
          );
          if (age > flushInterval) {
            _logger.info(
              'Falling behind (oldest event: ${age.inSeconds}s old), '
              'scheduling immediate flush',
            );
            // Schedule next flush immediately (non-blocking)
            Future.microtask(() => flushOneBatch());
          }
        }
      } else if (result == UploadResult.networkError ||
          result == UploadResult.serverError) {
        _handleFailure();
      }
    } finally {
      _isFlushing = false;
    }
  }

  /// Manually flush ALL events to server
  ///
  /// Uploads events that existed at the time flush was called.
  /// Use this for manual flush operations (e.g., app shutdown, user action).
  ///
  /// Returns a [FlushResult] indicating the operation completed. Note that flush
  /// is a best-effort operation that may partially succeed.
  Future<FlushResult> flush() async {
    // Check remote settings state
    final remoteState = getRemoteEnablementState();
    if (remoteState != RemoteEnablementState.enabled) {
      _logger.debug('Flush skipped - remote settings state: $remoteState');
      return FlushResult();
    }

    // If already flushing, update cutoff to now and wait for completion
    if (_isFlushing) {
      _logger.debug('Already flushing, extending cutoff and waiting');
      _flushCutoffTimestamp = clock.now();
      if (_flushCompleter != null) {
        return await _flushCompleter!.future;
      }
      // This shouldn't happen but return success if completer is null for some reason
      return FlushResult();
    }

    _isFlushing = true;
    _flushCompleter = Completer<FlushResult>();

    try {
      // Check backoff
      if (_isInBackoff()) {
        _logger.debug('In backoff period, skipping flush');
        final result = FlushResult();
        _flushCompleter!.complete(result);
        return result;
      }

      // Check connectivity
      if (wifiOnly && !(await _isWiFiConnected())) {
        _logger.debug('Not on WiFi, skipping flush');
        final result = FlushResult();
        _flushCompleter!.complete(result);
        return result;
      }

      // Get the newest event timestamp when flush started - only upload events with timestamp <= this
      // This ensures we only upload events that existed when flush was called
      final newestEvent = await eventQueue.fetchNewest();

      if (newestEvent == null) {
        _logger.debug('No events to flush');
        final result = FlushResult();
        _flushCompleter!.complete(result);
        return result;
      }

      _flushCutoffTimestamp = newestEvent.timestamp;
      _logger.debug(
        'Flush starting - will upload events with timestamp <= $_flushCutoffTimestamp',
      );

      // Upload batches until queue is empty OR we hit events newer than cutoff
      // The cutoff can be dynamically extended by concurrent flush() calls
      var oldestEvent = await eventQueue.fetchOldest();
      while (oldestEvent != null &&
          !oldestEvent.timestamp.isAfter(_flushCutoffTimestamp!)) {
        // Check if we entered backoff during multi-batch flush
        if (_isInBackoff()) {
          _logger.debug('Entered backoff during flush, stopping');
          break;
        }

        final result = await _uploadBatch();

        if (result == UploadResult.success) {
          _consecutiveFailures = 0;
          _requestAllowedAfterTime = null;
          // Yield to event loop to prevent UI blocking on web
          await Future.delayed(Duration.zero);
          // Fetch next oldest event for next iteration
          oldestEvent = await eventQueue.fetchOldest();
        } else if (result == UploadResult.networkError ||
            result == UploadResult.serverError) {
          _handleFailure();
          break; // Stop flushing on error
        } else {
          break; // No more events or backoff
        }
      }

      // Log completion reason
      if (oldestEvent == null) {
        _logger.debug('Flush complete - no more events');
      } else if (oldestEvent.timestamp.isAfter(_flushCutoffTimestamp!)) {
        _logger.debug(
          'Flush complete - remaining events (timestamp: ${oldestEvent.timestamp}) are newer than cutoff ($_flushCutoffTimestamp)',
        );
      }

      final result = FlushResult();
      _flushCompleter?.complete(result);
      return result;
    } finally {
      // Complete the completer if it hasn't been completed yet (exception case)
      if (_flushCompleter != null && !_flushCompleter!.isCompleted) {
        _flushCompleter!.complete(FlushResult());
      }
      _flushCompleter = null;
      _isFlushing = false;
    }
  }

  /// Upload a single batch of events
  Future<UploadResult> _uploadBatch() async {
    try {
      // Get the oldest event to determine which session/user to upload
      // This ensures FIFO order and prevents abandoned events
      final oldestEvent = await eventQueue.fetchOldest();

      if (oldestEvent == null) {
        return UploadResult.success; // No events to upload
      }

      final sessionId = oldestEvent.sessionId;
      final distinctId = oldestEvent.distinctId;

      // Fetch batch of events for this sessionId and distinctId
      final events = await eventQueue.fetchBatch(
        sessionId: sessionId,
        distinctId: distinctId,
        maxBytes: maxPayloadBytes,
        maxCount: maxEventsPerBatch,
      );

      if (events.isEmpty) {
        return UploadResult
            .success; // No events (shouldn't happen but defensive)
      }

      final targetDistinctId = distinctId;

      _logger.debug(
        'Uploading ${events.length} events '
        '(IDs: ${events.map((e) => e.id).join(", ")}) '
        'distinctId: $targetDistinctId, session: $sessionId)',
      );

      // Get Session object for this sessionId (may be old session!)
      // Session metadata is created when startRecording() is called, so this should always exist
      final session = await eventQueue.getSessionMetadata(sessionId);

      if (session == null) {
        _logger.error(
          'No session metadata found for session $sessionId - this should not happen!',
        );
        return UploadResult.networkError;
      }

      // Get sequence number for THIS session being uploaded (per-session, not global)
      final lastSeq = await eventQueue.getLastSequenceNumber(sessionId);
      final sequenceNumber =
          lastSeq + 1; // Next sequence number for this session

      // Serialize payload using injected serializer
      final serialized = await payloadSerializer.serialize(
        events,
        session,
        targetDistinctId,
        sequenceNumber,
      );

      // Build request
      final queryParams = payloadSerializer.buildQueryParams(
        session,
        targetDistinctId,
        sequenceNumber,
      );
      final uri = Uri.parse(_endpoint).replace(queryParameters: queryParams);

      _logger.debug('POST $uri');
      _logger.debug('Headers: ${serialized.headers.keys.join(", ")}');
      _logger.debug('Compressed: ${serialized.isCompressed}');

      // Send request
      final response = await _httpClient
          .post(uri, headers: serialized.headers, body: serialized.body)
          .timeout(const Duration(seconds: 30));

      _logger.debug('Response status: ${response.statusCode}');

      // Handle response
      if (response.statusCode == 200) {
        // Success - remove uploaded events from queue
        _logger.debug(
          'Removing ${events.length} events from queue (IDs: ${events.map((e) => e.id).join(", ")})',
        );
        await eventQueue.remove(events);

        // Verify events were removed
        final remainingOldest = await eventQueue.fetchOldest();
        _logger.debug(
          'After removal, oldest event: ${remainingOldest?.id} (session: ${remainingOldest?.sessionId}, distinctId: ${remainingOldest?.distinctId})',
        );

        // Persist sequence number to storage for THIS session
        try {
          await eventQueue.updateSequenceNumber(session.id, sequenceNumber);
          _logger.debug(
            'Persisted sequence number: $sequenceNumber for session: ${session.id}',
          );
        } catch (e) {
          _logger.error('Failed to persist sequence number: $e');
          // Continue - this is not critical for functionality
        }

        _logger.info('Successfully uploaded ${events.length} events');
        return UploadResult.success;
      } else if (response.statusCode == 429) {
        _logger.warning('Rate limited (429)');
        return UploadResult.quotaExceeded;
      } else if (response.statusCode >= 500) {
        _logger.error('Server error: ${response.statusCode}');
        return UploadResult.serverError;
      } else {
        _logger.error('Client error: ${response.statusCode}');
        return UploadResult.networkError;
      }
    } catch (e) {
      _logger.error('Upload failed: $e');
      return UploadResult.networkError;
    }
  }

  /// Check if WiFi is connected
  Future<bool> _isWiFiConnected() async {
    try {
      final results = await _connectivity.checkConnectivity();

      // Check if any connection is WiFi/Ethernet
      return results.any(
        (result) =>
            result == ConnectivityResult.wifi ||
            result == ConnectivityResult.ethernet,
      );
    } catch (e) {
      _logger.error('Connectivity check failed: $e');
      return false; // Assume not WiFi on error
    }
  }

  /// Check if we're in backoff period
  bool _isInBackoff() {
    if (_requestAllowedAfterTime == null) return false;
    return clock.now().isBefore(_requestAllowedAfterTime!);
  }

  /// Handle upload failure with exponential backoff
  void _handleFailure() {
    _consecutiveFailures++;

    if (_consecutiveFailures >= _failuresBeforeBackoff) {
      // Calculate exponential backoff: 2^(failures-1) * 60 seconds + random jitter
      final backoffFactor = 1 << (_consecutiveFailures - 1); // 2^(failures-1)
      var backoffDuration = _minBackoff * backoffFactor;

      // Add random jitter (0-29 seconds) to prevent thundering herd
      final jitterSeconds = Random().nextInt(30);
      backoffDuration = backoffDuration + Duration(seconds: jitterSeconds);

      // Cap at max backoff
      if (backoffDuration > _maxBackoff) {
        backoffDuration = _maxBackoff;
      }

      _requestAllowedAfterTime = clock.now().add(backoffDuration);

      _logger.warning(
        'Backoff activated for $backoffDuration '
        '(failures: $_consecutiveFailures, jitter: ${jitterSeconds}s)',
      );
    }
  }

  /// Dispose resources
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    stopAutoFlush();
  }
}

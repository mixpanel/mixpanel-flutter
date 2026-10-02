import '../../models/session_event.dart';

/// Optional capability implemented by persistent queues that can be shared by
/// multiple runtimes, such as browser tabs.
///
/// Leases are per session, like mixpanel-js's per-replay lock. A tab only
/// uploads sessions it recorded and sessions no live tab owns, so contention
/// arises only when several tabs drain the same expired session; the lease
/// keeps one runtime at a time uploading that session. As with the mixpanel-js
/// lock timeout, a tab frozen past the lease TTL may repeat a batch another
/// tab has since sent; the sequence number never moves backwards.
abstract interface class UploadLease {
  /// Identity this runtime holds the lease under.
  ///
  /// Stable across page reloads so a tab that reloads mid-upload can take its
  /// own lease straight back instead of waiting for the TTL to expire.
  String get uploadLeaseOwnerId;

  Future<bool> acquireUploadLease({
    required String ownerId,
    required String sessionId,
    required Duration ttl,
  });

  Future<void> releaseUploadLease({
    required String ownerId,
    required String sessionId,
  });
}

/// Optional capability for queues that can atomically delete an acknowledged
/// batch and advance its replay sequence number.
abstract interface class AtomicUploadCommit {
  Future<void> commitUploadedBatch({
    required List<PersistedSessionReplayEvent> events,
    required String sessionId,
    required int sequenceNumber,
  });
}

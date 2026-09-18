import '../../models/session_event.dart';

/// Optional capability implemented by persistent queues that can be shared by
/// multiple runtimes, such as browser tabs.
///
/// The upload service uses this lease to ensure only one runtime reads,
/// uploads, removes, and advances sequence numbers for a batch at a time.
abstract interface class UploadLease {
  Future<bool> acquireUploadLease({
    required String ownerId,
    required Duration ttl,
  });

  Future<void> releaseUploadLease({required String ownerId});
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

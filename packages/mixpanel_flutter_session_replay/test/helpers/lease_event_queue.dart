import 'package:mixpanel_flutter_session_replay/src/internal/storage/upload_lease.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session_event.dart';

import 'in_memory_event_queue.dart';

/// In-memory queue that also offers the cross-tab upload lease, recording the
/// owner ids the upload service uses so tests can assert on lease identity.
class LeaseEventQueue extends InMemoryEventQueue
    implements UploadLease, AtomicUploadCommit {
  LeaseEventQueue({this.uploadLeaseOwnerId = 'tab-owner'});

  @override
  final String uploadLeaseOwnerId;

  final List<String> acquireOwnerIds = [];
  final List<String> acquireSessionIds = [];
  final List<String> releaseOwnerIds = [];
  final List<String> releaseSessionIds = [];

  /// Results returned by successive acquire calls; `true` once exhausted.
  final List<bool> acquireResults = [];

  /// Invoked on every acquire with the 1-based call count, before the result
  /// is returned. Lets a test act as another tab between lease renewals.
  void Function(int acquireCount)? onAcquire;

  /// When true, commits behave as if another tab took the lease meanwhile.
  bool commitLoses = false;
  int commitCount = 0;

  @override
  Future<bool> acquireUploadLease({
    required String ownerId,
    required String sessionId,
    required Duration ttl,
  }) async {
    acquireOwnerIds.add(ownerId);
    acquireSessionIds.add(sessionId);
    onAcquire?.call(acquireOwnerIds.length);
    return acquireResults.isEmpty ? true : acquireResults.removeAt(0);
  }

  @override
  Future<void> releaseUploadLease({
    required String ownerId,
    required String sessionId,
  }) async {
    releaseOwnerIds.add(ownerId);
    releaseSessionIds.add(sessionId);
  }

  @override
  Future<void> commitUploadedBatch({
    required List<PersistedSessionReplayEvent> events,
    required String sessionId,
    required int sequenceNumber,
  }) async {
    commitCount++;
    if (commitLoses) {
      throw const UploadLeaseLostException('lease held by another tab');
    }
    await remove(events);
    await updateSequenceNumber(sessionId, sequenceNumber);
  }
}

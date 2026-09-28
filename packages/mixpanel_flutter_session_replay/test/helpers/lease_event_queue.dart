import 'package:mixpanel_flutter_session_replay/src/internal/storage/upload_lease.dart';

import 'in_memory_event_queue.dart';

/// In-memory queue that also offers the cross-tab upload lease, recording the
/// owner ids the upload service uses so tests can assert on lease identity.
class LeaseEventQueue extends InMemoryEventQueue implements UploadLease {
  LeaseEventQueue({this.uploadLeaseOwnerId = 'tab-owner'});

  @override
  final String uploadLeaseOwnerId;

  final List<String> acquireOwnerIds = [];
  final List<String> releaseOwnerIds = [];

  /// Results returned by successive acquire calls; `true` once exhausted.
  final List<bool> acquireResults = [];

  @override
  Future<bool> acquireUploadLease({
    required String ownerId,
    required Duration ttl,
  }) async {
    acquireOwnerIds.add(ownerId);
    return acquireResults.isEmpty ? true : acquireResults.removeAt(0);
  }

  @override
  Future<void> releaseUploadLease({required String ownerId}) async {
    releaseOwnerIds.add(ownerId);
  }
}

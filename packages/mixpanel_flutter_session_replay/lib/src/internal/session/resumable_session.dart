import '../../models/session.dart';
import 'session_lifetime.dart';

/// A persisted session and the deadlines that must travel with it while it
/// waits for remote settings. Keeping them together prevents partial clears.
class ResumableSession {
  final Session session;
  final DateTime? idleExpiry;
  const ResumableSession(this.session, {this.idleExpiry});

  bool isExpired(Duration? maximumDuration) =>
      SessionLifetime.expired(idleExpiry) ||
      (maximumDuration != null &&
          SessionLifetime.expired(session.startTime.add(maximumDuration)));
}

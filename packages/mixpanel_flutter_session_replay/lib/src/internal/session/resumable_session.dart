import '../../models/session.dart';
import 'session_lifetime.dart';

/// A persisted session and the deadlines that must travel with it while it
/// waits for remote settings. Keeping them together prevents partial clears.
class ResumableSession {
  final Session session;
  final DateTime? idleExpiry;
  final DateTime? backgroundExpiry;
  const ResumableSession(
    this.session, {
    this.idleExpiry,
    this.backgroundExpiry,
  });

  bool isExpired(Duration? maximumDuration) =>
      SessionLifetime.expired(idleExpiry) ||
      SessionLifetime.expired(backgroundExpiry) ||
      (maximumDuration != null &&
          SessionLifetime.expired(session.startTime.add(maximumDuration)));
}

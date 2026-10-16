import '../../models/session.dart';
import 'session_lifetime.dart';

/// A persisted session and the deadlines that must travel with it while it
/// waits for remote settings. Keeping them together prevents partial clears.
class ResumableSession {
  final Session session;
  final DateTime? idleExpiry;

  /// When the user was last active, if the record carried it.
  ///
  /// [idleExpiry] was computed at page load, before remote settings were
  /// known. Keeping the raw activity time lets the resume decision apply
  /// whichever idle timeout is in force by the time it is taken.
  final DateTime? lastActivity;

  const ResumableSession(this.session, {this.idleExpiry, this.lastActivity});

  /// Whether this replay is over under the limits in force now.
  ///
  /// [idleTimeout] is re-applied to [lastActivity] rather than trusted from
  /// [idleExpiry], because a remote timeout that shrank after the page
  /// loaded would otherwise never reach this decision.
  bool isExpired(Duration? maximumDuration, {Duration? idleTimeout}) =>
      SessionLifetime.expired(idleExpiry) ||
      (lastActivity != null &&
          idleTimeout != null &&
          SessionLifetime.expired(lastActivity!.add(idleTimeout))) ||
      (maximumDuration != null &&
          SessionLifetime.expired(session.startTime.add(maximumDuration)));
}

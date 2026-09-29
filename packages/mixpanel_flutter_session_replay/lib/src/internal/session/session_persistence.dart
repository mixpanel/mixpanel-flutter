import 'package:clock/clock.dart';

import '../logger.dart';
import 'recording_limits.dart';
import 'resumable_session.dart';
import 'session_lifetime.dart';

/// Writes a replay's deadlines to storage, in epoch milliseconds.
typedef SessionDeadlineWriter =
    Future<void> Function(
      String sessionId,
      int idleExpiresMs,
      int maxExpiresMs,
      int? backgroundExpiresMs,
    );

/// Carries a replay across page loads: stores its deadlines while it records
/// and hands a stored replay back to be resumed.
///
/// Native platforms start every process with a fresh replay and use
/// [SessionPersistence.none].
abstract class SessionPersistence {
  /// Persists nothing and never offers a session to resume.
  factory SessionPersistence.none() = _NoSessionPersistence;

  /// Takes the replay waiting to be resumed, if any. It is offered only once.
  ResumableSession? takeResumable();

  /// Drops the replay waiting to be resumed and expires its stored record, so
  /// a later page load cannot resume it either. Returns the dropped replay.
  ResumableSession? discardResumable();

  /// Stores [lifetime]'s deadlines after user activity. Writes are held back
  /// by [expiryWriteDebounce].
  void recordActivity(String sessionId, SessionLifetime lifetime);

  /// Stores [lifetime]'s deadlines immediately.
  void writeNow(String sessionId, SessionLifetime lifetime);

  /// Marks a stored replay as expired so a page reload cannot resume it.
  void expire(String sessionId);
}

class _NoSessionPersistence implements SessionPersistence {
  @override
  ResumableSession? takeResumable() => null;

  @override
  ResumableSession? discardResumable() => null;

  @override
  void recordActivity(String sessionId, SessionLifetime lifetime) {}

  @override
  void writeNow(String sessionId, SessionLifetime lifetime) {}

  @override
  void expire(String sessionId) {}
}

/// Persists deadlines through a [SessionDeadlineWriter] (IndexedDB on web)
/// and offers the replay a previous page load left recording.
class StoredSessionPersistence implements SessionPersistence {
  final SessionDeadlineWriter _write;
  final MixpanelLogger _logger;
  ResumableSession? _resumable;

  /// Last time deadlines were written, for the activity debounce.
  DateTime? _lastWriteTime;

  StoredSessionPersistence({
    required SessionDeadlineWriter write,
    required MixpanelLogger logger,
    ResumableSession? resumable,
  }) : _write = write,
       _logger = logger,
       _resumable = resumable;

  /// Offers [session] for resume once remote settings allow recording.
  void stageResume(ResumableSession session) {
    _resumable = session;
    _logger.info(
      'Session ${session.session.id} is eligible for resume; waiting for '
      'remote settings',
      tag: 'coordinator',
    );
  }

  @override
  ResumableSession? takeResumable() {
    final resumable = _resumable;
    _resumable = null;
    return resumable;
  }

  @override
  ResumableSession? discardResumable() {
    final resumable = takeResumable();
    if (resumable != null) expire(resumable.session.id);
    return resumable;
  }

  @override
  void recordActivity(String sessionId, SessionLifetime lifetime) {
    final last = _lastWriteTime;
    if (last != null && clock.now().difference(last) < expiryWriteDebounce) {
      return;
    }
    _save(sessionId, lifetime);
  }

  @override
  void writeNow(String sessionId, SessionLifetime lifetime) {
    _lastWriteTime = null;
    _save(sessionId, lifetime);
  }

  void _save(String sessionId, SessionLifetime lifetime) {
    // Without a maximum deadline there is no active replay to store.
    final maximumExpiry = lifetime.maximumExpiry;
    if (maximumExpiry == null) return;
    _lastWriteTime = clock.now();
    _write(
      sessionId,
      lifetime.persistedIdleExpiry!.millisecondsSinceEpoch,
      maximumExpiry.millisecondsSinceEpoch,
      lifetime.backgroundExpiry?.millisecondsSinceEpoch,
    ).catchError((Object e) {
      _logger.error(
        'Failed to persist idle expiry: $e',
        null,
        null,
        'coordinator',
      );
    });
  }

  /// Not debounced: a stop must reach storage even if an activity write just
  /// happened. IndexedDB runs readwrite transactions on the same store in
  /// creation order, so an earlier in-flight activity write cannot land after
  /// this one and revive the session.
  @override
  void expire(String sessionId) {
    _lastWriteTime = null;
    final expiredMs = clock.now().millisecondsSinceEpoch - 1;
    _write(sessionId, expiredMs, expiredMs, null).catchError((Object e) {
      _logger.error(
        'Failed to expire persisted session: $e',
        null,
        null,
        'coordinator',
      );
    });
  }
}

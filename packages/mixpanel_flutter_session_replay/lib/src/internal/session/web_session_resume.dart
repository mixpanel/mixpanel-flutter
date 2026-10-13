import 'package:clock/clock.dart';

import '../storage/indexed_db_event_queue.dart';
import '../logger.dart';
import '../../models/session.dart';
import 'resumable_session.dart';

/// Returns the replay this tab left recording on a previous page load, if
/// none of its deadlines has passed.
Future<ResumableSession?> checkWebSessionResume({
  required IndexedDbEventQueue queue,
  required Duration maxSessionDuration,
  required MixpanelLogger logger,
  Duration? idleTimeout,
}) async {
  // Only a session this tab recorded is a candidate, as in mixpanel-js where
  // the registry is keyed by tab id. Metadata rebuilt by the uploader is
  // unowned and already expired, so it is never returned here.
  final metadata = await queue.getLatestSessionMetadata(ownedBy: queue.ownerId);
  if (metadata == null) {
    logger.debug('No session recorded by this tab found in IndexedDB');
    return null;
  }

  final sessionId = metadata['session_id'] as String;
  final sessionStartTime = metadata['session_start_time'] as int;
  final now = clock.now().millisecondsSinceEpoch;

  final maxExpiresMs = metadata['max_expires'] as int?;
  if (maxExpiresMs != null && now >= maxExpiresMs) {
    logger.info('Previous session $sessionId expired (max duration exceeded)');
    return null;
  }

  // A stored deadline bakes in the timeout that was in effect when it was
  // written, so a timeout that shrank since then would not be honored. The
  // deadline the current timeout implies is therefore computed too, and the
  // earlier of the two wins: a shrunk timeout must cut the window short, and
  // a lengthened one must not revive a replay the stored deadline ended.
  final storedIdleExpiresMs = metadata['idle_expires'] as int?;
  final lastActivityMs = metadata['last_activity'] as int?;
  final currentIdleExpiresMs = (lastActivityMs != null && idleTimeout != null)
      ? lastActivityMs + idleTimeout.inMilliseconds
      : null;
  final idleExpiresMs = switch ((storedIdleExpiresMs, currentIdleExpiresMs)) {
    (final int stored, final int current) =>
      stored < current ? stored : current,
    (final int stored, null) => stored,
    (null, final int current) => current,
    _ => null,
  };
  if (idleExpiresMs != null && now >= idleExpiresMs) {
    logger.info('Previous session $sessionId expired (idle timeout exceeded)');
    return null;
  }

  if (maxExpiresMs == null && idleExpiresMs == null) {
    final sessionAge = now - sessionStartTime;
    if (sessionAge > maxSessionDuration.inMilliseconds) {
      logger.info(
        'Previous session $sessionId too old (no expiry data, age check)',
      );
      return null;
    }
  }

  logger.info('Resuming previous session: $sessionId');
  return ResumableSession(
    Session(
      id: sessionId,
      startTime: DateTime.fromMillisecondsSinceEpoch(
        sessionStartTime,
        isUtc: true,
      ),
      status: SessionStatus.active,
    ),
    idleExpiry: idleExpiresMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(idleExpiresMs),
    // Raw, so the resume decision can re-apply whatever timeout is in force
    // once remote settings have landed. The expiry above was computed with
    // the locally configured one, which is all that exists at page load.
    lastActivity: lastActivityMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lastActivityMs),
  );
}

Future<void> updateWebSessionExpiry({
  required IndexedDbEventQueue queue,
  required String sessionId,
  required int idleExpiresMs,
  required int maxExpiresMs,
  int? lastActivityMs,
}) async {
  await queue.updateSessionExpiry(
    sessionId: sessionId,
    idleExpiresMs: idleExpiresMs,
    maxExpiresMs: maxExpiresMs,
    lastActivityMs: lastActivityMs,
  );
}

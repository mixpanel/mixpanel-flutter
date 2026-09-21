import '../storage/event_queue_interface.dart';
import '../storage/indexed_db_event_queue.dart';
import '../logger.dart';
import '../../models/session.dart';

/// Result of checking whether a previous web session can be resumed.
class SessionResumeInfo {
  final Session session;
  final int lastSequenceNumber;

  /// The persisted idle deadline, when one was stored.
  ///
  /// Carried through so a resumed session keeps the remaining inactivity
  /// window instead of being granted a fresh one.
  final DateTime? idleExpiry;

  SessionResumeInfo({
    required this.session,
    required this.lastSequenceNumber,
    this.idleExpiry,
  });
}

Future<SessionResumeInfo?> checkWebSessionResume({
  required EventQueue queue,
  required Duration idleTimeout,
  required Duration maxSessionDuration,
  required MixpanelLogger logger,
}) async {
  if (queue is! IndexedDbEventQueue) return null;

  final metadata = await queue.getLatestSessionMetadata(ownedBy: queue.ownerId);
  if (metadata == null) {
    logger.debug('No existing session metadata found in IndexedDB');
    return null;
  }

  final sessionId = metadata['session_id'] as String;
  if (!await queue.claimSessionOwnership(sessionId)) {
    logger.debug('Session $sessionId is active in another browser tab');
    return null;
  }
  final sessionStartTime = metadata['session_start_time'] as int;
  final lastSequenceNumber = metadata['last_sequence_number'] as int? ?? -1;
  final now = DateTime.now().millisecondsSinceEpoch;

  final maxExpiresMs = metadata['max_expires'] as int?;
  if (maxExpiresMs != null && now > maxExpiresMs) {
    logger.info('Previous session $sessionId expired (max duration exceeded)');
    return null;
  }

  final idleExpiresMs = metadata['idle_expires'] as int?;
  if (idleExpiresMs != null && now > idleExpiresMs) {
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
  return SessionResumeInfo(
    session: Session(
      id: sessionId,
      startTime: DateTime.fromMillisecondsSinceEpoch(
        sessionStartTime,
        isUtc: true,
      ),
      status: SessionStatus.active,
    ),
    lastSequenceNumber: lastSequenceNumber,
    idleExpiry: idleExpiresMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(idleExpiresMs),
  );
}

Future<void> updateWebSessionExpiry({
  required EventQueue queue,
  required String sessionId,
  required int idleExpiresMs,
  required int maxExpiresMs,
  required MixpanelLogger logger,
}) async {
  if (queue is! IndexedDbEventQueue) return;
  await queue.updateSessionExpiry(
    sessionId: sessionId,
    idleExpiresMs: idleExpiresMs,
    maxExpiresMs: maxExpiresMs,
  );
}

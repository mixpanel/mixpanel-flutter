import 'package:clock/clock.dart';

import '../storage/event_queue_interface.dart';
import '../storage/indexed_db_event_queue.dart';
import '../logger.dart';
import '../../models/session.dart';
import 'resumable_session.dart';

/// Result of checking whether a previous web session can be resumed.
class SessionResumeInfo extends ResumableSession {
  final int lastSequenceNumber;

  SessionResumeInfo({
    required Session session,
    required this.lastSequenceNumber,
    DateTime? idleExpiry,
    DateTime? backgroundExpiry,
  }) : super(
         session,
         idleExpiry: idleExpiry,
         backgroundExpiry: backgroundExpiry,
       );
}

Future<SessionResumeInfo?> checkWebSessionResume({
  required EventQueue queue,
  required Duration maxSessionDuration,
  required MixpanelLogger logger,
}) async {
  if (queue is! IndexedDbEventQueue) return null;

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
  final lastSequenceNumber = metadata['last_sequence_number'] as int? ?? -1;
  final now = clock.now().millisecondsSinceEpoch;

  final maxExpiresMs = metadata['max_expires'] as int?;
  if (maxExpiresMs != null && now >= maxExpiresMs) {
    logger.info('Previous session $sessionId expired (max duration exceeded)');
    return null;
  }

  final idleExpiresMs = metadata['idle_expires'] as int?;
  if (idleExpiresMs != null && now >= idleExpiresMs) {
    logger.info('Previous session $sessionId expired (idle timeout exceeded)');
    return null;
  }

  final backgroundExpiresMs = metadata['background_expires'] as int?;
  if (backgroundExpiresMs != null && now >= backgroundExpiresMs) {
    logger.info(
      'Previous session $sessionId expired (background timeout exceeded)',
    );
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
    backgroundExpiry: backgroundExpiresMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(backgroundExpiresMs),
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
  int? backgroundExpiresMs,
  required MixpanelLogger logger,
}) async {
  if (queue is! IndexedDbEventQueue) return;
  await queue.updateSessionExpiry(
    sessionId: sessionId,
    idleExpiresMs: idleExpiresMs,
    maxExpiresMs: maxExpiresMs,
    backgroundExpiresMs: backgroundExpiresMs,
  );
}

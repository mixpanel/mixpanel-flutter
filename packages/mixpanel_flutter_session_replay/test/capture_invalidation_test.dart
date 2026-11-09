import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/capture/capture_invalidation.dart';

void main() {
  group('CaptureInvalidation', () {
    test('an undisturbed capture is neither cancelled nor discarded', () {
      final invalidation = CaptureInvalidation();
      final ticket = invalidation.begin();

      expect(invalidation.isCancelled(ticket), isFalse);
      expect(invalidation.discardsAcquired(ticket), isFalse);
    });

    test('a stop cancels acquisition but keeps an acquired frame', () {
      // GIVEN a capture in flight when recording stops
      final invalidation = CaptureInvalidation();
      final ticket = invalidation.begin();

      // WHEN
      invalidation.noteStop();

      // THEN pixels must not be read any more, but a frame that was already
      // acquired stays with the replay it was captured for
      expect(invalidation.isCancelled(ticket), isTrue);
      expect(invalidation.discardsAcquired(ticket), isFalse);
    });

    test('a pause cancels acquisition and discards an acquired frame', () {
      final invalidation = CaptureInvalidation();
      final ticket = invalidation.begin();

      invalidation.notePause();

      expect(invalidation.isCancelled(ticket), isTrue);
      expect(invalidation.discardsAcquired(ticket), isTrue);
    });

    test('a capture begun after a pause is unaffected by it', () {
      final invalidation = CaptureInvalidation();
      invalidation.notePause();

      final ticket = invalidation.begin();

      expect(invalidation.isCancelled(ticket), isFalse);
      expect(invalidation.discardsAcquired(ticket), isFalse);
    });

    test('a pause followed by a stop still discards the older frame', () {
      final invalidation = CaptureInvalidation();
      final ticket = invalidation.begin();

      invalidation.notePause();
      invalidation.noteStop();

      expect(invalidation.discardsAcquired(ticket), isTrue);
    });
  });
}

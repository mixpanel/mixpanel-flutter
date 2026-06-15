import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session/session_manager.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session.dart';

void main() {
  group('SessionManager', () {
    group('startNewSession', () {
      test(
        'creates session with active status, current timestamp, and UUID v4 ID',
        () {
          fakeAsync((async) {
            // GIVEN
            final expectedTime = clock.now();
            final uuidV4Pattern = RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            );
            final manager = SessionManager();

            // WHEN
            final session = manager.startNewSession();

            // THEN
            expect(session.status, SessionStatus.active);
            expect(session.startTime, expectedTime);
            expect(session.id, matches(uuidV4Pattern));
          });
        },
      );

      test('generates unique IDs for consecutive sessions', () {
        // GIVEN
        final manager = SessionManager();

        // WHEN
        final session1 = manager.startNewSession();
        final session2 = manager.startNewSession();

        // THEN
        expect(session1.id, isNot(equals(session2.id)));
      });

      test('replaces current session on each call', () {
        // GIVEN
        final manager = SessionManager();
        final firstSession = manager.startNewSession();

        // WHEN
        final secondSession = manager.startNewSession();

        // THEN
        final currentSession = manager.getCurrentSession();
        expect(currentSession.id, secondSession.id);
        expect(currentSession.id, isNot(equals(firstSession.id)));
      });
    });

    group('getCurrentSession', () {
      test('returns existing session when one has been started', () {
        // GIVEN
        final manager = SessionManager();
        final startedSession = manager.startNewSession();

        // WHEN
        final currentSession = manager.getCurrentSession();

        // THEN
        expect(identical(currentSession, startedSession), true);
      });

      test('creates new session when none exists', () {
        // GIVEN
        final expectedStatus = SessionStatus.active;
        final manager = SessionManager();

        // WHEN
        final session = manager.getCurrentSession();

        // THEN
        expect(session.id, isNotEmpty);
        expect(session.status, expectedStatus);
      });

      test('returns same instance on multiple calls', () {
        // GIVEN
        final manager = SessionManager();

        // WHEN
        final session1 = manager.getCurrentSession();
        final session2 = manager.getCurrentSession();

        // THEN
        expect(identical(session1, session2), true);
      });
    });
  });
}

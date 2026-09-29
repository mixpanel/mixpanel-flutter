import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session/idle_timeout_timer.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session/session_lifetime.dart';

void main() {
  group('SessionLifetime.expiredDeadline', () {
    final start = DateTime.utc(2026, 1, 1);

    SessionLifetime lifetimeWithBothDeadlinesAt(DateTime deadline) {
      final lifetime = SessionLifetime(
        idleTimer: IdleTimeoutTimer(
          timeout: const Duration(minutes: 1),
          onTimeout: () {},
        ),
        maximumDuration: const Duration(minutes: 1),
        onIdleExpired: () {},
        onMaximumExpired: () {},
      );
      withClock(Clock.fixed(start), () {
        lifetime.begin(start);
        lifetime.recordActivity(deadline: deadline);
      });
      addTearDown(lifetime.dispose);
      return lifetime;
    }

    test('is null while both deadlines are ahead', () {
      // GIVEN
      final lifetime = lifetimeWithBothDeadlinesAt(
        start.add(const Duration(minutes: 1)),
      );

      // WHEN / THEN
      withClock(Clock.fixed(start), () {
        expect(lifetime.expiredDeadline(), isNull);
      });
    });

    test('reports the maximum when both have passed', () {
      // GIVEN
      final lifetime = lifetimeWithBothDeadlinesAt(
        start.add(const Duration(seconds: 30)),
      );

      // WHEN / THEN
      withClock(Clock.fixed(start.add(const Duration(minutes: 2))), () {
        expect(lifetime.expiredDeadline(), ExpiredDeadline.maximum);
      });
    });

    test('reports idle only when asked to include it', () {
      // GIVEN an idle deadline before the maximum
      final lifetime = lifetimeWithBothDeadlinesAt(
        start.add(const Duration(seconds: 30)),
      );

      // WHEN / THEN
      withClock(Clock.fixed(start.add(const Duration(seconds: 45))), () {
        expect(lifetime.expiredDeadline(), ExpiredDeadline.idle);
        expect(lifetime.expiredDeadline(includeIdle: false), isNull);
      });
    });
  });
}

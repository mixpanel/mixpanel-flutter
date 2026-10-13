import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session/recording_limits.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session/session_lifetime.dart';

SessionLifetime? lifetimeRef;

void main() {
  group('SessionLifetime maximum timer', () {
    final start = DateTime.utc(2026, 1, 1);

    test('rearms when the clock moved back before it fired', () {
      // GIVEN a replay with a one minute maximum and no idle timeout, so the
      // maximum timer is the only thing that can end it
      FakeAsync().run((async) {
        var endedCalls = 0;
        var now = start;
        withClock(Clock(() => now), () {
          final lifetime = SessionLifetime(
            limits: const RecordingDurationLimits(
              maximum: Duration(minutes: 1),
            ),
            onIdleExpired: () {},
            onMaximumExpired: () {
              // Mirrors the coordinator: ends only if the wall clock agrees.
              if (lifetimeRef!.isMaximumExpired) endedCalls++;
            },
          );
          lifetimeRef = lifetime;
          addTearDown(lifetime.dispose);
          lifetime.begin(start);

          // WHEN the wall clock jumps back 30s while the timer counts down
          now = start.add(const Duration(seconds: 30));
          async.elapse(const Duration(minutes: 1));

          // THEN the timer fired but declined to end the replay, and rearmed
          expect(endedCalls, 0);

          // AND once the wall clock does pass the deadline, it ends
          now = start.add(const Duration(minutes: 5));
          async.elapse(const Duration(minutes: 1));
          expect(endedCalls, 1);
        });
      });
    });
  });

  group('SessionLifetime.expiredDeadline', () {
    final start = DateTime.utc(2026, 1, 1);

    SessionLifetime lifetimeWithBothDeadlinesAt(DateTime deadline) {
      final lifetime = SessionLifetime(
        limits: const RecordingDurationLimits(
          maximum: Duration(minutes: 1),
          idle: Duration(minutes: 1),
        ),
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

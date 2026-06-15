import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/capture/capture_scheduler.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';

void main() {
  group('CaptureScheduler', () {
    late CaptureScheduler scheduler;

    setUp(() {
      scheduler = CaptureScheduler(logger: MixpanelLogger(LogLevel.none));
    });

    tearDown(() {
      scheduler.dispose();
    });

    group('canCapture', () {
      test('returns true when no capture has occurred yet', () {
        // GIVEN - fresh scheduler (setUp)

        // WHEN
        final result = scheduler.canCapture();

        // THEN
        expect(result, true);
      });

      test('returns false when capture is in progress', () {
        // GIVEN
        scheduler.markCaptureStarted();

        // WHEN
        final result = scheduler.canCapture();

        // THEN
        expect(result, false);
      });

      test(
        'returns false when less than minInterval has elapsed since last capture',
        () {
          // GIVEN
          scheduler.markCaptureStarted();
          scheduler.markCaptureCompleted();
          // markCaptureCompleted just happened, so < 500ms have elapsed

          // WHEN
          final result = scheduler.canCapture();

          // THEN
          expect(result, false);
        },
      );

      test('returns true after minInterval has elapsed since last capture', () {
        fakeAsync((async) {
          // GIVEN
          final scheduler = CaptureScheduler(
            logger: MixpanelLogger(LogLevel.none),
          );

          scheduler.markCaptureStarted();
          scheduler.markCaptureCompleted();
          async.elapse(Duration(milliseconds: 500));

          // WHEN
          final result = scheduler.canCapture();

          // THEN
          expect(result, true);

          scheduler.dispose();
        });
      });
    });

    test('multiple start/complete cycles work correctly', () {
      fakeAsync((async) {
        // GIVEN
        final scheduler = CaptureScheduler(
          logger: MixpanelLogger(LogLevel.none),
        );

        // First cycle
        scheduler.markCaptureStarted();
        scheduler.markCaptureCompleted();
        async.elapse(Duration(milliseconds: 500));

        // THEN - can capture again
        expect(scheduler.canCapture(), true);

        // Second cycle
        scheduler.markCaptureStarted();
        expect(scheduler.canCapture(), false);
        scheduler.markCaptureCompleted();

        // THEN - rate limited again
        expect(scheduler.canCapture(), false);

        scheduler.dispose();
      });
    });

    group('scheduleAfterRateLimit', () {
      test('returns null when capture is in progress', () {
        // GIVEN
        scheduler.markCaptureStarted();
        var callbackInvoked = false;

        // WHEN
        final result = scheduler.scheduleAfterRateLimit(() {
          callbackInvoked = true;
        });

        // THEN
        expect(result, isNull);
        expect(callbackInvoked, false);
      });

      test('returns null when timer is already active', () {
        // GIVEN - Schedule a first callback to create an active timer
        scheduler.scheduleAfterRateLimit(() {});

        // WHEN - Try to schedule a second
        final result = scheduler.scheduleAfterRateLimit(() {});

        // THEN
        expect(result, isNull);
      });

      test('returns Duration.zero for first capture', () {
        // GIVEN - no previous captures

        // WHEN
        final result = scheduler.scheduleAfterRateLimit(() {});

        // THEN
        expect(result, Duration.zero);
      });

      test('executes callback when Duration.zero timer fires', () {
        fakeAsync((async) {
          // GIVEN
          final scheduler = CaptureScheduler(
            logger: MixpanelLogger(LogLevel.none),
          );
          var callbackInvoked = false;

          // WHEN - first call returns Duration.zero
          scheduler.scheduleAfterRateLimit(() {
            callbackInvoked = true;
          });
          async.elapse(Duration.zero);

          // THEN
          expect(callbackInvoked, true);

          scheduler.dispose();
        });
      });

      test('executes callback after remaining rate limit time elapses', () {
        fakeAsync((async) {
          // GIVEN
          final scheduler = CaptureScheduler(
            minInterval: Duration(milliseconds: 100),
            logger: MixpanelLogger(LogLevel.none),
          );
          var callbackInvoked = false;

          scheduler.markCaptureStarted();
          scheduler.markCaptureCompleted();
          async.elapse(Duration(milliseconds: 50));

          // WHEN
          scheduler.scheduleAfterRateLimit(() {
            callbackInvoked = true;
          });

          // THEN - callback should not fire before remaining time
          async.elapse(Duration(milliseconds: 49));
          expect(callbackInvoked, false);

          // THEN - callback should fire after remaining time
          async.elapse(Duration(milliseconds: 1));
          expect(callbackInvoked, true);

          scheduler.dispose();
        });
      });

      test(
        'returns remaining duration when rate limit is partially elapsed',
        () {
          fakeAsync((async) {
            // GIVEN
            final expectedRemainingMs = 70;
            final scheduler = CaptureScheduler(
              minInterval: Duration(milliseconds: 100),
              logger: MixpanelLogger(LogLevel.none),
            );

            scheduler.markCaptureStarted();
            scheduler.markCaptureCompleted();
            async.elapse(Duration(milliseconds: 30));

            // WHEN
            final result = scheduler.scheduleAfterRateLimit(() {});

            // THEN
            expect(result, isNotNull);
            expect(result!.inMilliseconds, expectedRemainingMs);

            scheduler.dispose();
          });
        },
      );
    });

    group('dispose', () {
      test('cancels active timer so callback never fires', () {
        fakeAsync((async) {
          // GIVEN
          final scheduler = CaptureScheduler(
            logger: MixpanelLogger(LogLevel.none),
          );
          var callbackInvoked = false;

          // Schedule a callback (Duration.zero for first capture)
          scheduler.scheduleAfterRateLimit(() {
            callbackInvoked = true;
          });

          // WHEN - dispose before timer fires
          scheduler.dispose();

          // Advance well past when the timer would have fired
          async.elapse(Duration(seconds: 1));

          // THEN
          expect(callbackInvoked, false);
        });
      });
    });

    group('custom minInterval', () {
      test('respects custom interval duration', () {
        fakeAsync((async) {
          // GIVEN
          final customInterval = Duration(milliseconds: 100);
          final scheduler = CaptureScheduler(
            minInterval: customInterval,
            logger: MixpanelLogger(LogLevel.none),
          );

          scheduler.markCaptureStarted();
          scheduler.markCaptureCompleted();

          // WHEN - less than custom interval has elapsed
          async.elapse(Duration(milliseconds: 50));

          // THEN - should still be rate limited
          expect(scheduler.canCapture(), false);

          // WHEN - wait for rest of interval
          async.elapse(Duration(milliseconds: 50));

          // THEN - should be allowed
          expect(scheduler.canCapture(), true);

          scheduler.dispose();
        });
      });
    });
  });
}

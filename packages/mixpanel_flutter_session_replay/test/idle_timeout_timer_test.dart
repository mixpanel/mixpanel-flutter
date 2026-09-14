import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session/idle_timeout_timer.dart';

void main() {
  group('IdleTimeoutTimer', () {
    test('fires callback after timeout duration', () {
      fakeAsync((async) {
        // GIVEN
        var callCount = 0;
        final timer = IdleTimeoutTimer(
          timeout: const Duration(minutes: 30),
          onTimeout: () => callCount++,
        );

        // WHEN
        timer.start();
        async.elapse(const Duration(minutes: 30));

        // THEN
        expect(callCount, 1);

        timer.dispose();
      });
    });

    test('does not fire before timeout duration', () {
      fakeAsync((async) {
        // GIVEN
        var callCount = 0;
        final timer = IdleTimeoutTimer(
          timeout: const Duration(minutes: 30),
          onTimeout: () => callCount++,
        );

        // WHEN
        timer.start();
        async.elapse(const Duration(minutes: 29));

        // THEN
        expect(callCount, 0);

        timer.dispose();
      });
    });

    test('reset extends the timeout', () {
      fakeAsync((async) {
        // GIVEN
        var callCount = 0;
        final timer = IdleTimeoutTimer(
          timeout: const Duration(minutes: 30),
          onTimeout: () => callCount++,
        );

        // WHEN
        timer.start();
        async.elapse(const Duration(minutes: 20));
        timer.reset(); // reset at 20 min — should fire at 50 min total
        async.elapse(const Duration(minutes: 20));

        // THEN — still within new timeout window
        expect(callCount, 0);

        // WHEN — pass the new timeout
        async.elapse(const Duration(minutes: 10));

        // THEN
        expect(callCount, 1);

        timer.dispose();
      });
    });

    test('stop cancels the timer', () {
      fakeAsync((async) {
        // GIVEN
        var callCount = 0;
        final timer = IdleTimeoutTimer(
          timeout: const Duration(minutes: 30),
          onTimeout: () => callCount++,
        );

        // WHEN
        timer.start();
        async.elapse(const Duration(minutes: 15));
        timer.stop();
        async.elapse(const Duration(minutes: 30));

        // THEN
        expect(callCount, 0);

        timer.dispose();
      });
    });

    test('dispose cancels the timer', () {
      fakeAsync((async) {
        // GIVEN
        var callCount = 0;
        final timer = IdleTimeoutTimer(
          timeout: const Duration(minutes: 30),
          onTimeout: () => callCount++,
        );

        // WHEN
        timer.start();
        async.elapse(const Duration(minutes: 15));
        timer.dispose();
        async.elapse(const Duration(minutes: 30));

        // THEN
        expect(callCount, 0);
      });
    });

    test('zero timeout disables the timer', () {
      fakeAsync((async) {
        // GIVEN
        var callCount = 0;
        final timer = IdleTimeoutTimer(
          timeout: Duration.zero,
          onTimeout: () => callCount++,
        );

        // WHEN
        timer.start();
        async.elapse(const Duration(hours: 1));

        // THEN
        expect(callCount, 0);

        timer.dispose();
      });
    });

    test('fires only once per start cycle', () {
      fakeAsync((async) {
        // GIVEN
        var callCount = 0;
        final timer = IdleTimeoutTimer(
          timeout: const Duration(minutes: 5),
          onTimeout: () => callCount++,
        );

        // WHEN
        timer.start();
        async.elapse(const Duration(minutes: 30));

        // THEN — only fires once, not repeatedly
        expect(callCount, 1);

        timer.dispose();
      });
    });
  });
}

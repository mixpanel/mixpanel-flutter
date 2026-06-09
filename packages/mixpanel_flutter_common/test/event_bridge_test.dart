import 'dart:async';

import 'package:test/test.dart';
import 'package:mixpanel_flutter_common/mixpanel_flutter_common.dart';

void main() {
  group('MixpanelEventBridge', () {
    test('subscriber receives events emitted after listen', () async {
      final received = <MixpanelEvent>[];
      final sub = MixpanelEventBridge.events.listen(received.add);

      MixpanelEventBridge.notifyListeners(eventName: 'A', properties: {'x': 1});
      MixpanelEventBridge.notifyListeners(eventName: 'B');

      // Stream delivery is async — flush the microtask queue.
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(2));
      expect(received[0].eventName, 'A');
      expect(received[0].properties, {'x': 1});
      expect(received[1].eventName, 'B');
      expect(received[1].properties, isNull);

      await sub.cancel();
    });

    test(
      'multiple subscribers each see every event (broadcast semantics)',
      () async {
        final a = <String>[];
        final b = <String>[];
        final subA = MixpanelEventBridge.events.listen(
          (e) => a.add(e.eventName),
        );
        final subB = MixpanelEventBridge.events.listen(
          (e) => b.add(e.eventName),
        );

        MixpanelEventBridge.notifyListeners(eventName: 'evt');
        await Future<void>.delayed(Duration.zero);

        expect(a, ['evt']);
        expect(b, ['evt']);

        await subA.cancel();
        await subB.cancel();
      },
    );

    test('late subscribers miss prior events (no replay buffer)', () async {
      // Emit before anyone is listening.
      MixpanelEventBridge.notifyListeners(eventName: 'lost');
      await Future<void>.delayed(Duration.zero);

      final received = <String>[];
      final sub = MixpanelEventBridge.events.listen(
        (e) => received.add(e.eventName),
      );

      MixpanelEventBridge.notifyListeners(eventName: 'after');
      await Future<void>.delayed(Duration.zero);

      expect(received, ['after']); // 'lost' never reaches the late subscriber
      await sub.cancel();
    });

    test('nullable properties pass through unchanged', () async {
      final received = <MixpanelEvent>[];
      final sub = MixpanelEventBridge.events.listen(received.add);

      MixpanelEventBridge.notifyListeners(eventName: 'null-props');
      MixpanelEventBridge.notifyListeners(
        eventName: 'empty-props',
        properties: const {},
      );
      MixpanelEventBridge.notifyListeners(
        eventName: 'with-props',
        properties: const {'a': 1, 'b': 'two'},
      );
      await Future<void>.delayed(Duration.zero);

      expect(received[0].properties, isNull);
      expect(received[1].properties, isEmpty);
      expect(received[2].properties, {'a': 1, 'b': 'two'});

      await sub.cancel();
    });

    group('lifecycle callbacks', () {
      tearDown(() {
        // Detach callbacks so they don't bleed into unrelated tests that
        // subscribe/cancel through the same singleton controller.
        MixpanelEventBridge.setLifecycleCallbacks();
      });

      test('onActivate fires when first listener subscribes', () async {
        var activations = 0;
        MixpanelEventBridge.setLifecycleCallbacks(
          onActivate: () => activations++,
        );

        final sub = MixpanelEventBridge.events.listen((_) {});
        expect(activations, 1);

        await sub.cancel();
      });

      test('onActivate fires only on the 0→1 transition', () async {
        var activations = 0;
        MixpanelEventBridge.setLifecycleCallbacks(
          onActivate: () => activations++,
        );

        final a = MixpanelEventBridge.events.listen((_) {});
        final b = MixpanelEventBridge.events.listen((_) {});
        expect(activations, 1);

        await a.cancel();
        await b.cancel();
      });

      test('onDeactivate fires only when the last listener cancels', () async {
        var deactivations = 0;
        MixpanelEventBridge.setLifecycleCallbacks(
          onDeactivate: () => deactivations++,
        );

        final a = MixpanelEventBridge.events.listen((_) {});
        final b = MixpanelEventBridge.events.listen((_) {});

        await a.cancel();
        expect(deactivations, 0);

        await b.cancel();
        expect(deactivations, 1);
      });

      test('re-subscribing after cancel re-activates', () async {
        var activations = 0;
        var deactivations = 0;
        MixpanelEventBridge.setLifecycleCallbacks(
          onActivate: () => activations++,
          onDeactivate: () => deactivations++,
        );

        final first = MixpanelEventBridge.events.listen((_) {});
        await first.cancel();
        final second = MixpanelEventBridge.events.listen((_) {});

        expect(activations, 2);
        expect(deactivations, 1);

        await second.cancel();
      });
    });

    test('exception in one listener does not block other listeners', () async {
      // When a broadcast listener throws synchronously, the exception is
      // delivered to the surrounding zone's uncaught-error handler rather
      // than aborting other subscriptions. runZonedGuarded captures it so
      // the test framework doesn't see an unhandled error.
      final survivors = <String>[];
      final errors = <Object>[];

      await runZonedGuarded(
        () async {
          final boom = MixpanelEventBridge.events.listen((_) {
            throw StateError('listener exploded');
          });
          final ok = MixpanelEventBridge.events.listen(
            (e) => survivors.add(e.eventName),
          );

          MixpanelEventBridge.notifyListeners(eventName: 'evt');
          await Future<void>.delayed(Duration.zero);

          await boom.cancel();
          await ok.cancel();
        },
        (error, _) {
          errors.add(error);
        },
      );

      expect(survivors, ['evt']);
      expect(errors, hasLength(1));
      expect(errors.first, isA<StateError>());
    });

    group('source wiring hook', () {
      tearDown(() {
        // Reset both the wiring hook AND lifecycle callbacks — the
        // `hook runs before listeners observe onActivate` test installs
        // a lifecycle callback inside the hook, and if its assertion
        // fails before the inline reset, the leaked closure would bleed
        // into subsequent tests that subscribe through the singleton
        // controller.
        MixpanelEventBridge.setSourceWiringHook();
        MixpanelEventBridge.setLifecycleCallbacks();
      });

      test('fires the first time events is read', () {
        var calls = 0;
        MixpanelEventBridge.setSourceWiringHook(() => calls++);

        // Access alone (no listener) is enough — wiring needs to be in
        // place before .listen() triggers onActivate.
        // ignore: unused_local_variable
        final _ = MixpanelEventBridge.events;
        expect(calls, 1);
      });

      test('does not fire on subsequent reads of events', () {
        var calls = 0;
        MixpanelEventBridge.setSourceWiringHook(() => calls++);

        MixpanelEventBridge.events;
        MixpanelEventBridge.events;
        MixpanelEventBridge.events;
        expect(calls, 1);
      });

      test('does not fire when events is never read', () {
        var calls = 0;
        MixpanelEventBridge.setSourceWiringHook(() => calls++);
        expect(calls, 0);
      });

      test('re-registering after consumption fires again on next read', () {
        var calls = 0;
        MixpanelEventBridge.setSourceWiringHook(() => calls++);
        MixpanelEventBridge.events; // consumes the first hook
        MixpanelEventBridge.setSourceWiringHook(() => calls++);
        MixpanelEventBridge.events; // consumes the second hook
        expect(calls, 2);
      });

      test('hook runs before listeners observe onActivate', () async {
        // The wiring hook is `mixpanel_flutter`'s opportunity to install
        // its lifecycle callbacks. If onActivate fires before the hook
        // runs, the native side never gets a startEventBridge.
        final order = <String>[];
        MixpanelEventBridge.setSourceWiringHook(() {
          order.add('hook');
          MixpanelEventBridge.setLifecycleCallbacks(
            onActivate: () => order.add('activate'),
          );
        });

        final sub = MixpanelEventBridge.events.listen((_) {});
        expect(order, ['hook', 'activate']);

        await sub.cancel();
        // Lifecycle callbacks are also reset in the group tearDown — no
        // need to reset inline here.
      });
    });
  });
}

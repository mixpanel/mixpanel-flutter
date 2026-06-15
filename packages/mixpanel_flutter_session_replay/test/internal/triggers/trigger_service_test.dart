// Tests drive MixpanelEventBridge.notifyListeners directly to simulate
// upstream events. The member is @internal but reserved for Mixpanel-authored
// downstream packages like this one.
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_common/mixpanel_flutter_common.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/triggers/trigger_service.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/event_trigger.dart';

void main() {
  final logger = MixpanelLogger(LogLevel.none);

  late List<double> fired;
  late TriggerService service;

  setUp(() {
    fired = <double>[];
    service = TriggerService(logger: logger, onTriggerFired: fired.add);
  });

  tearDown(() async {
    await service.dispose();
  });

  test('does not fire when triggers map is null', () async {
    // updateTriggers(null) cancels any subscription; events are ignored.
    service.updateTriggers(null);
    MixpanelEventBridge.notifyListeners(eventName: 'Login');
    await Future<void>.delayed(Duration.zero);
    expect(fired, isEmpty);
  });

  test('does not fire when triggers map is empty', () async {
    // updateTriggers({}) cancels any subscription; events are ignored.
    service.updateTriggers(const {});
    MixpanelEventBridge.notifyListeners(eventName: 'Login');
    await Future<void>.delayed(Duration.zero);
    expect(fired, isEmpty);
  });

  test('fires callback with trigger percentage when event matches', () async {
    service.updateTriggers({'Login': const EventTrigger(percentage: 42)});
    MixpanelEventBridge.notifyListeners(eventName: 'Login');
    await Future<void>.delayed(Duration.zero);
    expect(fired, [42]);
  });

  test('does not fire when event name has no registered trigger', () async {
    service.updateTriggers({'Login': const EventTrigger(percentage: 100)});
    MixpanelEventBridge.notifyListeners(eventName: 'Logout');
    await Future<void>.delayed(Duration.zero);
    expect(fired, isEmpty);
  });

  test(
    'updateTriggers(null) clears all triggers and cancels subscription',
    () async {
      service.updateTriggers({'Login': const EventTrigger(percentage: 100)});
      service.updateTriggers(null);
      MixpanelEventBridge.notifyListeners(eventName: 'Login');
      await Future<void>.delayed(Duration.zero);
      expect(fired, isEmpty);
    },
  );

  test(
    'updateTriggers swaps the active trigger set without resubscribing',
    () async {
      service.updateTriggers({'A': const EventTrigger(percentage: 10)});

      MixpanelEventBridge.notifyListeners(eventName: 'A');
      await Future<void>.delayed(Duration.zero);
      expect(fired, [10]);

      service.updateTriggers({'B': const EventTrigger(percentage: 90)});
      MixpanelEventBridge.notifyListeners(
        eventName: 'A',
      ); // no longer registered
      MixpanelEventBridge.notifyListeners(eventName: 'B');
      await Future<void>.delayed(Duration.zero);
      expect(fired, [10, 90]);
    },
  );

  test(
    'updateTriggers is idempotent (does not create duplicate subscriptions)',
    () async {
      service.updateTriggers({'Once': const EventTrigger(percentage: 1)});
      service.updateTriggers({'Once': const EventTrigger(percentage: 1)});
      service.updateTriggers({'Once': const EventTrigger(percentage: 1)});

      MixpanelEventBridge.notifyListeners(eventName: 'Once');
      await Future<void>.delayed(Duration.zero);
      // Single subscription → callback fired once, not three times.
      expect(fired, [1]);
    },
  );

  test(
    'subscription is re-activated after going empty then non-empty',
    () async {
      service.updateTriggers({'A': const EventTrigger(percentage: 50)});
      service.updateTriggers(null); // cancel
      service.updateTriggers({
        'A': const EventTrigger(percentage: 75),
      }); // re-activate

      MixpanelEventBridge.notifyListeners(eventName: 'A');
      await Future<void>.delayed(Duration.zero);
      expect(fired, [75]);
    },
  );

  test('after dispose(), no further callbacks fire', () async {
    service.updateTriggers({'X': const EventTrigger(percentage: 100)});
    await service.dispose();

    MixpanelEventBridge.notifyListeners(eventName: 'X');
    await Future<void>.delayed(Duration.zero);
    expect(fired, isEmpty);
  });

  test('updateTriggers after dispose is a no-op', () async {
    await service.dispose();
    service.updateTriggers({'X': const EventTrigger(percentage: 100)});

    MixpanelEventBridge.notifyListeners(eventName: 'X');
    await Future<void>.delayed(Duration.zero);
    expect(fired, isEmpty);
  });

  test('disable() suppresses callbacks; enable() restores them', () async {
    service.updateTriggers({'Login': const EventTrigger(percentage: 100)});

    // Default: enabled — fires.
    expect(service.isEnabled, isTrue);
    MixpanelEventBridge.notifyListeners(eventName: 'Login');
    await Future<void>.delayed(Duration.zero);
    expect(fired, [100]);

    // Disabled — callback suppressed even though the trigger matches.
    service.disable();
    expect(service.isEnabled, isFalse);
    MixpanelEventBridge.notifyListeners(eventName: 'Login');
    await Future<void>.delayed(Duration.zero);
    expect(fired, [100]);

    // Re-enabled — fires again.
    service.enable();
    expect(service.isEnabled, isTrue);
    MixpanelEventBridge.notifyListeners(eventName: 'Login');
    await Future<void>.delayed(Duration.zero);
    expect(fired, [100, 100]);
  });

  test('events that pass propertyFilters fire the callback', () async {
    service.updateTriggers({
      'Purchase': const EventTrigger(
        percentage: 25,
        propertyFilters: {
          '>': [
            {'var': 'amount'},
            100,
          ],
        },
      ),
    });

    MixpanelEventBridge.notifyListeners(
      eventName: 'Purchase',
      properties: {'amount': 50},
    );
    await Future<void>.delayed(Duration.zero);
    expect(fired, isEmpty);

    MixpanelEventBridge.notifyListeners(
      eventName: 'Purchase',
      properties: {'amount': 250},
    );
    await Future<void>.delayed(Duration.zero);
    expect(fired, [25]);
  });
}

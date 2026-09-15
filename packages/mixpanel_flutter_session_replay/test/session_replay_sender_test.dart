import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session_replay_sender.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionReplaySender', () {
    late List<MethodCall> methodCalls;
    late List<MethodCall> mixpanelCalls;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      methodCalls = [];
      mixpanelCalls = [];

      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.mixpanel.flutter_session_replay'),
        (call) async {
          methodCalls.add(call);
          return null;
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('mixpanel_flutter'),
        (call) async {
          mixpanelCalls.add(call);
          return null;
        },
      );
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.mixpanel.flutter_session_replay'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('mixpanel_flutter'),
        null,
      );
    });

    test(
      'register invokes registerSuperProperties on method channel',
      () async {
        // GIVEN
        final properties = {'\$mp_replay_id': 'test-id'};

        // WHEN
        await SessionReplaySender.register(properties);

        // THEN
        expect(methodCalls, hasLength(1));
        expect(methodCalls[0].method, 'registerSuperProperties');
        expect(methodCalls[0].arguments, {'\$mp_replay_id': 'test-id'});
      },
    );

    test(
      'unregister invokes unregisterSuperProperty on method channel',
      () async {
        // GIVEN
        const propertyName = '\$mp_replay_id';

        // WHEN
        await SessionReplaySender.unregister(propertyName);

        // THEN
        expect(methodCalls, hasLength(1));
        expect(methodCalls[0].method, 'unregisterSuperProperty');
        expect(methodCalls[0].arguments, {'key': '\$mp_replay_id'});
      },
    );

    test('register does not throw when method channel fails', () async {
      // GIVEN - channel handler that throws
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.mixpanel.flutter_session_replay'),
            (call) async {
              throw PlatformException(code: 'ERROR', message: 'test error');
            },
          );

      // WHEN / THEN - should not throw
      await SessionReplaySender.register({'\$mp_replay_id': 'test-id'});
    });

    test('unregister does not throw when method channel fails', () async {
      // GIVEN - channel handler that throws
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.mixpanel.flutter_session_replay'),
            (call) async {
              throw PlatformException(code: 'ERROR', message: 'test error');
            },
          );

      // WHEN / THEN - should not throw
      await SessionReplaySender.unregister('\$mp_replay_id');
    });

    test('register routes through mixpanel_flutter on macOS', () async {
      // GIVEN
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      // WHEN
      await SessionReplaySender.register({'\$mp_replay_id': 'test-id'});

      // THEN
      expect(methodCalls, isEmpty);
      expect(mixpanelCalls, [
        isMethodCall(
          'registerSuperProperties',
          arguments: {
            'properties': {'\$mp_replay_id': 'test-id'},
          },
        ),
      ]);
    });

    test('unregister routes through mixpanel_flutter on macOS', () async {
      // GIVEN
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      // WHEN
      await SessionReplaySender.unregister('\$mp_replay_id');

      // THEN
      expect(methodCalls, isEmpty);
      expect(mixpanelCalls, [
        isMethodCall(
          'unregisterSuperProperty',
          arguments: {'propertyName': '\$mp_replay_id'},
        ),
      ]);
    });
  });
}

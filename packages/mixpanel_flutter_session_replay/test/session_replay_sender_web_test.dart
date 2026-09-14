@TestOn('browser')
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session_replay_sender.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mixpanelChannel = MethodChannel('mixpanel_flutter');
  const sessionReplayChannel = MethodChannel(
    'com.mixpanel.flutter_session_replay',
  );
  late List<MethodCall> mixpanelCalls;
  late List<MethodCall> sessionReplayCalls;

  setUp(() {
    mixpanelCalls = [];
    sessionReplayCalls = [];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(mixpanelChannel, (call) async {
      mixpanelCalls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(sessionReplayChannel, (call) async {
      sessionReplayCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(mixpanelChannel, null);
    messenger.setMockMethodCallHandler(sessionReplayChannel, null);
  });

  test('registers replay ID through mixpanel_flutter on web', () async {
    await SessionReplaySender.register({'\$mp_replay_id': 'replay-123'});

    expect(sessionReplayCalls, isEmpty);
    expect(mixpanelCalls, [
      isMethodCall(
        'registerSuperProperties',
        arguments: {
          'properties': {'\$mp_replay_id': 'replay-123'},
        },
      ),
    ]);
  });

  test('unregisters replay ID through mixpanel_flutter on web', () async {
    await SessionReplaySender.unregister('\$mp_replay_id');

    expect(sessionReplayCalls, isEmpty);
    expect(mixpanelCalls, [
      isMethodCall(
        'unregisterSuperProperty',
        arguments: {'propertyName': '\$mp_replay_id'},
      ),
    ]);
  });

  test('silently tolerates mixpanel_flutter being absent', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mixpanelChannel, null);

    await expectLater(
      SessionReplaySender.register({'\$mp_replay_id': 'replay-123'}),
      completes,
    );
    await expectLater(
      SessionReplaySender.unregister('\$mp_replay_id'),
      completes,
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';

import 'integration_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('live settings check returns enabled for a valid project token', (
    tester,
  ) async {
    expect(
      mixpanelToken,
      isNotEmpty,
      reason:
          'MIXPANEL_TOKEN must be provided via --dart-define or --dart-define-from-file',
    );

    final initResult = await MixpanelSessionReplay.initializeWithDependencies(
      token: mixpanelToken,
      distinctId: 'live-settings-test',
      options: SessionReplayOptions(
        logLevel: testLogLevel,
        autoRecordSessionsPercent: 100.0,
        flushInterval: Duration.zero,
        autoMaskedViews: {},
        platformOptions: const PlatformOptions(
          mobile: MobileOptions(wifiOnly: false),
        ),
      ),
      // No httpClient — uses real http.Client hitting production
    );

    expect(initResult.success, isTrue);
    final sdk = initResult.instance!;

    await tester.pumpWidget(
      MixpanelSessionReplayWidget(
        instance: sdk,
        child: const MaterialApp(home: SizedBox()),
      ),
    );
    await tester.pumpAndSettle();

    // Simulate foregrounding — triggers the real settings check
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(() => Future.delayed(Duration(seconds: 3)));
    await tester.pump();

    // After the live settings check completes, recording should be active
    expect(
      sdk.recordingState,
      RecordingState.recording,
      reason: 'Settings endpoint should return is_enabled=true for this token',
    );
  });
}

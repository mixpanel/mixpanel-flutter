import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';

import 'integration_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'recording blocked when remote settings returns is_enabled false',
    (tester) async {
      final (:client, :uploadRequests) = createTestHttpClient(
        settingsEnabled: false,
      );

      final initResult = await MixpanelSessionReplay.initializeWithDependencies(
        token: 'test-token-disabled',
        distinctId: 'user-disabled',
        options: SessionReplayOptions(
          logLevel: testLogLevel,
          autoRecordSessionsPercent: 100.0,
          flushInterval: Duration.zero,
          autoMaskedViews: {},
          platformOptions: const PlatformOptions(
            mobile: MobileOptions(wifiOnly: false),
          ),
        ),
        httpClient: client,
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

      // Simulate foregrounding - triggers settings check + auto-start at 100%
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(() => Future.delayed(Duration(milliseconds: 500)));
      await tester.pump();

      // After settings resolve as disabled, recording should be stopped
      expect(sdk.recordingState, RecordingState.notRecording);

      // Flush should produce no upload requests
      await tester.runAsync(() => sdk.flush());
      expect(
        uploadRequests,
        isEmpty,
        reason: 'No events should be uploaded when settings disabled',
      );
    },
  );

  testWidgets('recording proceeds when settings check fails in disabled mode', (
    tester,
  ) async {
    final (:client, :uploadRequests) = createTestHttpClient(
      settingsStatusCode: 500,
    );

    final initResult = await MixpanelSessionReplay.initializeWithDependencies(
      token: 'test-token-fail',
      distinctId: 'user-fail',
      options: SessionReplayOptions(
        logLevel: testLogLevel,
        autoRecordSessionsPercent: 100.0,
        flushInterval: Duration.zero,
        autoMaskedViews: {},
        platformOptions: const PlatformOptions(
          mobile: MobileOptions(wifiOnly: false),
        ),
      ),
      httpClient: client,
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

    // Simulate foregrounding - triggers settings check (returns 500) + auto-start at 100%
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(() => Future.delayed(Duration(milliseconds: 500)));
    await tester.pump();

    // Settings check failed but mode is disabled - recording proceeds with local config
    expect(sdk.recordingState, RecordingState.recording);
  });

  // --- Remote config mode tests ---

  testWidgets('disabled mode ignores remote recordSessionsPercent', (
    tester,
  ) async {
    // Server returns 0% but mode is disabled - should use local 100%
    final (:client, :uploadRequests) = createTestHttpClient(
      recordSessionsPercent: 0.0,
    );

    final initResult = await MixpanelSessionReplay.initializeWithDependencies(
      token: 'test-disabled-mode',
      distinctId: 'user-disabled-mode',
      options: SessionReplayOptions(
        logLevel: testLogLevel,
        autoRecordSessionsPercent: 100.0,
        flushInterval: Duration.zero,
        autoMaskedViews: {},
        remoteSettingsMode: RemoteSettingsMode.disabled,
        platformOptions: const PlatformOptions(
          mobile: MobileOptions(wifiOnly: false),
        ),
      ),
      httpClient: client,
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

    await simulateForegrounding(tester);

    // Remote 0% ignored, local 100% used - recording should start
    expect(sdk.recordingState, RecordingState.recording);
  });

  testWidgets('fallback mode applies remote recordSessionsPercent of 0', (
    tester,
  ) async {
    // Server returns 0% with fallback mode - should prevent recording
    final (:client, :uploadRequests) = createTestHttpClient(
      recordSessionsPercent: 0.0,
    );

    final initResult = await MixpanelSessionReplay.initializeWithDependencies(
      token: 'test-fallback-0pct',
      distinctId: 'user-fallback-0pct',
      options: SessionReplayOptions(
        logLevel: testLogLevel,
        autoRecordSessionsPercent: 100.0,
        flushInterval: Duration.zero,
        autoMaskedViews: {},
        remoteSettingsMode: RemoteSettingsMode.fallback,
        platformOptions: const PlatformOptions(
          mobile: MobileOptions(wifiOnly: false),
        ),
      ),
      httpClient: client,
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

    await simulateForegrounding(tester);

    // Remote 0% applied - recording should not start
    expect(sdk.recordingState, RecordingState.notRecording);
  });

  testWidgets('fallback mode uses local config when settings fetch fails', (
    tester,
  ) async {
    final (:client, :uploadRequests) = createTestHttpClient(
      settingsStatusCode: 500,
    );

    final initResult = await MixpanelSessionReplay.initializeWithDependencies(
      token: 'test-fallback-fail',
      distinctId: 'user-fallback-fail',
      options: SessionReplayOptions(
        logLevel: testLogLevel,
        autoRecordSessionsPercent: 100.0,
        flushInterval: Duration.zero,
        autoMaskedViews: {},
        remoteSettingsMode: RemoteSettingsMode.fallback,
        platformOptions: const PlatformOptions(
          mobile: MobileOptions(wifiOnly: false),
        ),
      ),
      httpClient: client,
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

    await simulateForegrounding(tester);

    // Fetch failed, no cache - falls back to local 100%, recording starts
    expect(sdk.recordingState, RecordingState.recording);
  });

  testWidgets('strict mode blocks recording when sdk_config is missing', (
    tester,
  ) async {
    // Server returns enabled but no sdk_config
    final (:client, :uploadRequests) = createTestHttpClient();

    final initResult = await MixpanelSessionReplay.initializeWithDependencies(
      token: 'test-strict-no-config',
      distinctId: 'user-strict-no-config',
      options: SessionReplayOptions(
        logLevel: testLogLevel,
        autoRecordSessionsPercent: 100.0,
        flushInterval: Duration.zero,
        autoMaskedViews: {},
        remoteSettingsMode: RemoteSettingsMode.strict,
        platformOptions: const PlatformOptions(
          mobile: MobileOptions(wifiOnly: false),
        ),
      ),
      httpClient: client,
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

    await simulateForegrounding(tester);

    // Strict mode: no sdk_config in response - recording blocked
    expect(sdk.recordingState, RecordingState.notRecording);
  });

  testWidgets('strict mode blocks recording when settings fetch fails', (
    tester,
  ) async {
    final (:client, :uploadRequests) = createTestHttpClient(
      settingsStatusCode: 500,
    );

    final initResult = await MixpanelSessionReplay.initializeWithDependencies(
      token: 'test-strict-fail',
      distinctId: 'user-strict-fail',
      options: SessionReplayOptions(
        logLevel: testLogLevel,
        autoRecordSessionsPercent: 100.0,
        flushInterval: Duration.zero,
        autoMaskedViews: {},
        remoteSettingsMode: RemoteSettingsMode.strict,
        platformOptions: const PlatformOptions(
          mobile: MobileOptions(wifiOnly: false),
        ),
      ),
      httpClient: client,
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

    await simulateForegrounding(tester);

    // Strict mode: fetch failed (from cache) - recording blocked
    expect(sdk.recordingState, RecordingState.notRecording);
  });

  testWidgets('strict mode allows recording when sdk_config is present', (
    tester,
  ) async {
    final (:client, :uploadRequests) = createTestHttpClient(
      recordSessionsPercent: 100.0,
    );

    final initResult = await MixpanelSessionReplay.initializeWithDependencies(
      token: 'test-strict-ok',
      distinctId: 'user-strict-ok',
      options: SessionReplayOptions(
        logLevel: testLogLevel,
        autoRecordSessionsPercent: 100.0,
        flushInterval: Duration.zero,
        autoMaskedViews: {},
        remoteSettingsMode: RemoteSettingsMode.strict,
        platformOptions: const PlatformOptions(
          mobile: MobileOptions(wifiOnly: false),
        ),
      ),
      httpClient: client,
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

    await simulateForegrounding(tester);

    // Strict mode: sdk_config present with 100% - recording starts
    expect(sdk.recordingState, RecordingState.recording);
  });
}

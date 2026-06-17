import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';

import 'integration_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app backgrounding triggers flush of pending events', (
    tester,
  ) async {
    final (:client, :uploadRequests) = createTestHttpClient();

    final initResult = await MixpanelSessionReplay.initializeWithDependencies(
      token: 'test-token-bg',
      distinctId: 'user-bg',
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
        child: MaterialApp(
          home: Scaffold(
            body: Container(width: 200, height: 200, color: Colors.green),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Simulate app foregrounding → auto-starts recording with 100%
    await simulateForegrounding(tester);
    expect(sdk.recordingState, RecordingState.recording);

    // FrameMonitor auto-captures on next frame, creating pending events
    await waitForAutomaticCapture(tester);

    // Verify no uploads yet (auto-flush is disabled with Duration.zero)
    expect(
      uploadRequests,
      isEmpty,
      reason: 'No flush should have occurred yet',
    );

    // Simulate app backgrounding - triggers LifecycleObserver →
    // onAppBackgrounded() → stopRecording() → flush()
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);

    // Wait for the fire-and-forget flush to complete
    await tester.runAsync(() => Future.delayed(Duration(milliseconds: 500)));

    // Verify backgrounding triggered the flush
    expect(
      uploadRequests,
      isNotEmpty,
      reason: 'Backgrounding should trigger flush of pending events',
    );

    // Verify recording was stopped
    expect(sdk.recordingState, RecordingState.notRecording);
  });

  testWidgets(
    'foreground → background → foreground cycle creates a new session',
    (tester) async {
      final (:client, :uploadRequests) = createTestHttpClient();

      final initResult = await MixpanelSessionReplay.initializeWithDependencies(
        token: 'test-token-cycle',
        distinctId: 'user-cycle',
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
          child: MaterialApp(
            home: Scaffold(
              body: Container(width: 200, height: 200, color: Colors.blue),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // --- First foreground session ---
      await simulateForegrounding(tester);
      expect(sdk.recordingState, RecordingState.recording);

      await waitForAutomaticCapture(tester);
      await tester.runAsync(() => sdk.flush());

      expect(
        uploadRequests,
        isNotEmpty,
        reason: 'First session should have flushed',
      );
      final firstReplayId =
          uploadRequests.last.url.queryParameters['replay_id'];
      expect(firstReplayId, isNotNull);

      // --- Background (stops recording, triggers flush) ---
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.runAsync(() => Future.delayed(Duration(milliseconds: 500)));
      expect(sdk.recordingState, RecordingState.notRecording);

      final uploadsAfterBackground = uploadRequests.length;

      // --- Second foreground (new session) ---
      await simulateForegrounding(tester);
      expect(sdk.recordingState, RecordingState.recording);

      await waitForAutomaticCapture(tester);
      await tester.runAsync(() => sdk.flush());

      // Verify new uploads were made
      expect(
        uploadRequests.length,
        greaterThan(uploadsAfterBackground),
        reason: 'Second session should have flushed',
      );

      final secondReplayId =
          uploadRequests.last.url.queryParameters['replay_id'];
      expect(secondReplayId, isNotNull);

      // The two foreground sessions should have different replay_ids
      expect(
        firstReplayId,
        isNot(equals(secondReplayId)),
        reason: 'Each foreground cycle should create a new replay session',
      );
    },
  );

  testWidgets(
    're-initialization disposes old instance and new instance captures and flushes independently',
    (tester) async {
      final (:client, :uploadRequests) = createTestHttpClient();

      // --- First instance ---
      final initResult1 =
          await MixpanelSessionReplay.initializeWithDependencies(
            token: 'test-token-reinit',
            distinctId: 'user-first',
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

      expect(initResult1.success, isTrue);
      final sdk1 = initResult1.instance!;

      await tester.pumpWidget(
        MixpanelSessionReplayWidget(
          instance: sdk1,
          child: MaterialApp(
            home: Scaffold(
              body: Container(width: 200, height: 200, color: Colors.blue),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Simulate app foregrounding → auto-starts recording
      await simulateForegrounding(tester);
      expect(sdk1.recordingState, RecordingState.recording);

      // Capture and flush first instance
      await waitForAutomaticCapture(tester);
      await tester.runAsync(() => sdk1.flush());

      expect(
        uploadRequests,
        isNotEmpty,
        reason: 'First instance should have flushed',
      );

      // Verify first instance used correct distinctId
      final firstRequest = uploadRequests.first;
      expect(firstRequest.url.queryParameters['distinct_id'], 'user-first');

      // Record how many uploads first instance made
      final firstInstanceUploadCount = uploadRequests.length;

      // --- Re-initialize with same token (disposes first instance) ---
      final initResult2 =
          await MixpanelSessionReplay.initializeWithDependencies(
            token: 'test-token-reinit',
            distinctId: 'user-second',
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

      expect(initResult2.success, isTrue);
      final sdk2 = initResult2.instance!;

      // First instance should no longer be recording
      expect(sdk1.recordingState, RecordingState.notRecording);

      // Rebuild widget tree with new instance
      await tester.pumpWidget(
        MixpanelSessionReplayWidget(
          instance: sdk2,
          child: MaterialApp(
            home: Scaffold(
              body: Container(width: 200, height: 200, color: Colors.red),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Simulate app foregrounding → auto-starts recording on new instance
      await simulateForegrounding(tester);
      expect(sdk2.recordingState, RecordingState.recording);

      // Capture and flush second instance
      await waitForAutomaticCapture(tester);
      await tester.runAsync(() => sdk2.flush());

      // Verify second instance produced new uploads
      expect(
        uploadRequests.length,
        greaterThan(firstInstanceUploadCount),
        reason: 'Second instance should have flushed new events',
      );

      // Verify second instance used correct distinctId
      final secondRequest = uploadRequests.last;
      expect(secondRequest.url.queryParameters['distinct_id'], 'user-second');

      // Verify the two instances used different replay_ids (different sessions)
      final firstReplayId = firstRequest.url.queryParameters['replay_id'];
      final secondReplayId = secondRequest.url.queryParameters['replay_id'];
      expect(firstReplayId, isNotNull);
      expect(secondReplayId, isNotNull);
      expect(
        firstReplayId,
        isNot(equals(secondReplayId)),
        reason: 'Re-initialization should create a new session',
      );
    },
  );
}

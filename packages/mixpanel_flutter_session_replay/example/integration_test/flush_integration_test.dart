import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';

import 'integration_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('flush with no events sends no upload requests', (tester) async {
    final (:client, :uploadRequests) = createTestHttpClient();

    final initResult = await MixpanelSessionReplay.initializeWithDependencies(
      token: 'test-token-empty',
      distinctId: 'user-empty',
      options: SessionReplayOptions(
        logLevel: testLogLevel,
        autoRecordSessionsPercent: 0,
        flushInterval: Duration.zero,
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

    await tester.runAsync(() => sdk.flush());

    expect(uploadRequests, isEmpty, reason: 'No events = no upload');
  });

  testWidgets('multiple captures batch into single upload', (tester) async {
    final (:client, :uploadRequests) = createTestHttpClient();

    final initResult = await MixpanelSessionReplay.initializeWithDependencies(
      token: 'test-token-multi',
      distinctId: 'user-multi',
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
            body: Container(width: 100, height: 100, color: Colors.red),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Simulate app foregrounding to trigger auto-start recording
    await simulateForegrounding(tester);

    // Trigger 3 automatic captures with 500ms+ gaps (CaptureScheduler rate limit)
    for (var i = 0; i < 3; i++) {
      await waitForAutomaticCapture(tester);
      // Wait past the 500ms rate limit before next capture
      await tester.runAsync(() => Future.delayed(Duration(milliseconds: 2000)));
    }

    await tester.runAsync(() => sdk.flush());

    expect(uploadRequests, isNotEmpty);

    // Count total events across all upload requests
    var totalEvents = 0;
    for (final request in uploadRequests) {
      final decompressed = gzip.decode(request.bodyBytes);
      final json = jsonDecode(utf8.decode(decompressed)) as List;
      totalEvents += json.length;
    }
    expect(totalEvents, 4); // 1 meta + 3 screenshots

    final replayIds = uploadRequests
        .map((r) => r.url.queryParameters['replay_id'])
        .toSet();
    expect(replayIds.length, 1, reason: 'All batches should share a session');
    expect(replayIds.first, isNotEmpty);
  });

  testWidgets(
    'sequence numbers increment across multiple flushes within a session',
    (tester) async {
      final (:client, :uploadRequests) = createTestHttpClient();

      final initResult = await MixpanelSessionReplay.initializeWithDependencies(
        token: 'test-token-seq',
        distinctId: 'user-seq',
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
              body: Container(width: 200, height: 200, color: Colors.purple),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await simulateForegrounding(tester);
      expect(sdk.recordingState, RecordingState.recording);

      // --- First capture + flush ---
      await waitForAutomaticCapture(tester);
      await tester.runAsync(() => sdk.flush());

      expect(uploadRequests, isNotEmpty, reason: 'First flush should upload');
      final firstSeq = int.parse(
        uploadRequests.last.url.queryParameters['seq']!,
      );

      // --- Second capture + flush (within same session) ---
      // Wait past the 500ms rate limit
      await tester.runAsync(() => Future.delayed(Duration(milliseconds: 2000)));
      await waitForAutomaticCapture(tester);
      await tester.runAsync(() => sdk.flush());

      expect(
        uploadRequests.length,
        greaterThan(1),
        reason: 'Second flush should upload',
      );
      final secondSeq = int.parse(
        uploadRequests.last.url.queryParameters['seq']!,
      );

      expect(
        secondSeq,
        firstSeq + 1,
        reason: 'Sequence number should increment by 1',
      );

      // All uploads should share the same replay_id (same session)
      final replayIds = uploadRequests
          .map((r) => r.url.queryParameters['replay_id'])
          .toSet();
      expect(
        replayIds.length,
        1,
        reason: 'All flushes within a session share the same replay_id',
      );
    },
  );
}

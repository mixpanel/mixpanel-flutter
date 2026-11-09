import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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
    expect(sdk.recordingState, RecordingState.recording);

    // Foregrounding pumps frames of its own. How many captures they produce
    // depends on timing: a frame inside the 500ms rate limit earns one
    // deferred capture. Let them settle and drain them, with the session's
    // meta event, so only the captures below are counted.
    await tester.runAsync(() => Future.delayed(Duration(milliseconds: 2000)));
    await tester.runAsync(() => sdk.flush());

    // The session opens with exactly one meta event, ahead of its snapshots.
    final openingTypes = [
      for (final request in uploadRequests)
        for (final event in _decodeEvents(request)) event['type'],
    ];
    expect(openingTypes.first, 4, reason: 'The session starts with meta');
    expect(openingTypes.where((type) => type == 4), hasLength(1));
    expect(openingTypes.skip(1), everyElement(2));
    final openingReplayIds = uploadRequests
        .map((r) => r.url.queryParameters['replay_id'])
        .toSet();
    uploadRequests.clear();

    // Trigger 3 automatic captures with 500ms+ gaps (CaptureScheduler rate limit)
    for (var i = 0; i < 3; i++) {
      await waitForAutomaticCapture(tester);
      // Wait past the 500ms rate limit before next capture
      await tester.runAsync(() => Future.delayed(Duration(milliseconds: 2000)));
    }

    await tester.runAsync(() => sdk.flush());

    expect(
      uploadRequests,
      hasLength(1),
      reason: 'All captures should go out in a single upload',
    );
    expect(
      _decodeEvents(uploadRequests.single).map((event) => event['type']),
      [2, 2, 2],
      reason: 'One full snapshot per capture, and no second meta event',
    );

    final replayIds = {
      ...openingReplayIds,
      ...uploadRequests.map((r) => r.url.queryParameters['replay_id']),
    };
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

/// The rrweb events in an upload request's gzipped JSON body.
List<Map<String, dynamic>> _decodeEvents(http.Request request) =>
    (jsonDecode(utf8.decode(gzip.decode(request.bodyBytes))) as List)
        .cast<Map<String, dynamic>>();

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';

import 'integration_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SDK initializes, captures, and flushes a well-formed request', (
    tester,
  ) async {
    final (:client, :uploadRequests) = createTestHttpClient();

    final initResult = await MixpanelSessionReplay.initializeWithDependencies(
      token: 'test-token-flush',
      distinctId: 'user-integration',
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

    // Simulate app foregrounding → auto-starts recording with 100%
    await simulateForegrounding(tester);
    expect(sdk.recordingState, RecordingState.recording);

    // FrameMonitor auto-captures on next frame
    await waitForAutomaticCapture(tester);

    await tester.runAsync(() => sdk.flush());

    // Verify an upload request was made
    expect(uploadRequests, isNotEmpty, reason: 'Expected at least one POST');

    final request = uploadRequests.first;

    // Verify URL and query params
    expect(request.url.host, 'api.mixpanel.com');
    expect(request.url.path, '/record');
    expect(request.url.queryParameters['format'], 'gzip');
    expect(request.url.queryParameters['distinct_id'], 'user-integration');
    expect(request.url.queryParameters['seq'], isNotNull);
    expect(request.url.queryParameters['replay_id'], isNotNull);

    // Verify auth header
    expect(request.headers['content-type'], contains('octet-stream'));
    final authHeader = request.headers['authorization']!;
    expect(authHeader, startsWith('Basic '));
    final decodedAuth = utf8.decode(
      base64Decode(authHeader.substring('Basic '.length)),
    );
    expect(decodedAuth, 'test-token-flush:');

    // Verify body is valid gzip containing JSON with our events
    final decompressed = gzip.decode(request.bodyBytes);
    final json = jsonDecode(utf8.decode(decompressed)) as List;
    expect(json, isNotEmpty);

    // Should contain a meta event and a screenshot event
    final types = json.map((e) => e['type'] as int).toSet();
    expect(types, contains(4), reason: 'Should contain a meta event');
    expect(types, contains(2), reason: 'Should contain a screenshot event');

    // Verify the screenshot has a valid JPEG embedded in the RRWeb DOM
    final screenshotEvent = json.firstWhere((e) => e['type'] == 2);
    final node = screenshotEvent['data']['node'] as Map<String, dynamic>;
    final html = (node['childNodes'] as List)[1] as Map<String, dynamic>;
    final body = (html['childNodes'] as List)[1] as Map<String, dynamic>;
    final screen = (body['childNodes'] as List)[0] as Map<String, dynamic>;
    final img = (screen['childNodes'] as List)[0] as Map<String, dynamic>;
    final src = img['attributes']['src'] as String;
    expect(src, startsWith('data:image/jpeg;base64,'));

    final jpegBytes = base64Decode(src.split(',')[1]);
    expect(jpegBytes[0], 0xFF);
    expect(jpegBytes[1], 0xD8);
  });

  testWidgets('tap interaction is captured and flushed', (tester) async {
    final (:client, :uploadRequests) = createTestHttpClient();

    final initResult = await MixpanelSessionReplay.initializeWithDependencies(
      token: 'test-token-tap',
      distinctId: 'user-tap',
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

    // Simulate app foregrounding → auto-starts recording
    await simulateForegrounding(tester);
    expect(sdk.recordingState, RecordingState.recording);

    // Wait for initial automatic capture
    await waitForAutomaticCapture(tester);

    // Wait past the 500ms rate limit before the tap
    await tester.runAsync(() => Future.delayed(Duration(milliseconds: 2000)));

    // Simulate a touch interaction
    await tester.tapAt(const Offset(100, 100));
    await tester.pump();

    // Wait for the tap-triggered capture to complete
    // CI emulators can take 1000ms+ per capture
    await tester.runAsync(() => Future.delayed(Duration(milliseconds: 2000)));

    await tester.runAsync(() => sdk.flush());

    expect(uploadRequests, isNotEmpty);

    // Collect all events across uploads
    var allEvents = <dynamic>[];
    for (final request in uploadRequests) {
      final decompressed = gzip.decode(request.bodyBytes);
      final json = jsonDecode(utf8.decode(decompressed)) as List;
      allEvents.addAll(json);
    }

    final types = allEvents.map((e) => e['type'] as int).toSet();
    expect(types, contains(4), reason: 'Should contain a meta event');
    expect(types, contains(2), reason: 'Should contain a screenshot event');
    expect(
      types,
      contains(3),
      reason: 'Should contain an interaction event from the tap',
    );

    // Verify the interaction event has correct structure
    final interactionEvent = allEvents.firstWhere((e) => e['type'] == 3);
    expect(
      interactionEvent['data']['source'],
      2,
      reason: 'Source 2 = mouse interaction',
    );
    expect(interactionEvent['data']['type'], 7, reason: 'Type 7 = touchStart');
    expect(interactionEvent['data']['x'], isNotNull);
    expect(interactionEvent['data']['y'], isNotNull);
  });

  testWidgets('identify() mid-session splits uploads by distinct_id', (
    tester,
  ) async {
    final (:client, :uploadRequests) = createTestHttpClient();

    final initResult = await MixpanelSessionReplay.initializeWithDependencies(
      token: 'test-token-identify',
      distinctId: 'anonymous-user',
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
            body: Container(width: 200, height: 200, color: Colors.orange),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await simulateForegrounding(tester);
    expect(sdk.recordingState, RecordingState.recording);

    // Capture events as anonymous user
    await waitForAutomaticCapture(tester);

    // Wait past the 500ms rate limit
    await tester.runAsync(() => Future.delayed(Duration(milliseconds: 2000)));

    // Identify as a logged-in user mid-session
    sdk.identify('logged-in-user');
    expect(sdk.distinctId, 'logged-in-user');

    // Capture events as logged-in user
    await waitForAutomaticCapture(tester);

    // Flush all pending events
    await tester.runAsync(() => sdk.flush());

    expect(
      uploadRequests.length,
      greaterThanOrEqualTo(2),
      reason: 'Should have at least 2 uploads (one per distinct_id batch)',
    );

    // Collect distinct_ids from all upload requests
    final distinctIds = uploadRequests
        .map((r) => r.url.queryParameters['distinct_id'])
        .toList();

    // Earlier uploads should use anonymous, later should use logged-in
    expect(
      distinctIds.first,
      'anonymous-user',
      reason: 'First batch should use original distinct_id',
    );
    expect(
      distinctIds.last,
      'logged-in-user',
      reason: 'Last batch should use identified distinct_id',
    );

    // All uploads should share the same replay_id (same session)
    final replayIds = uploadRequests
        .map((r) => r.url.queryParameters['replay_id'])
        .toSet();
    expect(
      replayIds.length,
      1,
      reason: 'identify() does not create a new session, just changes user',
    );
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';

/// Mixpanel project token provided via --dart-define or --dart-define-from-file.
///
/// Set via: --dart-define=MIXPANEL_TOKEN=your_token
/// Or via .vscode/settings.json: --dart-define-from-file=local.env
const mixpanelToken = String.fromEnvironment('MIXPANEL_TOKEN');

/// Log level for integration tests, controlled via --dart-define=LOG_LEVEL=debug.
///
/// Defaults to [LogLevel.none]. Valid values: none, error, warning, info, debug.
final LogLevel testLogLevel = _parseLogLevel(
  const String.fromEnvironment('LOG_LEVEL', defaultValue: 'none'),
);

LogLevel _parseLogLevel(String value) {
  return LogLevel.values.firstWhere(
    (l) => l.name == value.toLowerCase(),
    orElse: () => LogLevel.none,
  );
}

/// Creates a mock HTTP client that:
/// - Returns settings response for GET /settings requests
/// - Returns 200 for all other requests (upload) and records them
///
/// [settingsEnabled] controls the `is_enabled` value in the settings response.
/// [settingsStatusCode] controls the HTTP status code for the settings response.
/// [recordSessionsPercent] if non-null, includes `sdk_config.config` in the response.
({http.Client client, List<http.Request> uploadRequests}) createTestHttpClient({
  bool settingsEnabled = true,
  int settingsStatusCode = 200,
  double? recordSessionsPercent,
}) {
  final uploadRequests = <http.Request>[];

  final client = http_testing.MockClient((request) async {
    if (request.url.path == '/settings') {
      if (settingsStatusCode != 200) {
        return http.Response('Server Error', settingsStatusCode);
      }
      final responseBody = <String, dynamic>{
        'recording': {'is_enabled': settingsEnabled},
      };
      if (recordSessionsPercent != null) {
        responseBody['sdk_config'] = {
          'config': {'record_sessions_percent': recordSessionsPercent},
        };
      }
      return http.Response(jsonEncode(responseBody), 200);
    }

    uploadRequests.add(request);
    return http.Response('', 200);
  });

  return (client: client, uploadRequests: uploadRequests);
}

/// Simulates app foregrounding and waits for recording to start.
///
/// This triggers LifecycleObserver → onAppForegrounded() → auto-starts
/// recording. The delay allows the async settings check and session
/// initialization to complete.
Future<void> simulateForegrounding(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.runAsync(() => Future.delayed(Duration(milliseconds: 200)));
  await tester.pump();
}

/// Triggers an automatic screenshot capture via FrameMonitor.
///
/// Pumps a frame so FrameMonitor detects the recording state and triggers
/// a capture, then waits for the async capture pipeline to complete.
/// The capture pipeline (screenshot → compress → store) can take over 1s
/// on slow CI emulators, so we wait generously.
Future<void> waitForAutomaticCapture(WidgetTester tester) async {
  // Pump a frame to trigger FrameMonitor's persistent frame callback
  await tester.pump();
  // Wait for the async capture pipeline (screenshot → compress → store)
  // CI emulators can take 1000ms+ per capture (rendering + compression)
  await tester.runAsync(() => Future.delayed(Duration(milliseconds: 2000)));
}

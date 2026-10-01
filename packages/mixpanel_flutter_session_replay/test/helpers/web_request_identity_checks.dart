import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/settings/settings_service.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/settings/settings_storage_provider.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/upload/payload_serializer.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session.dart';
import 'package:web/web.dart' as web;

/// Each browser test suite runs in its own context: OS resolution is cached
/// once per SDK load, so install the user agent before making either request.
Future<void> checkWebRequestIdentity(
  String userAgent,
  String? expectedOs,
) async {
  (globalContext['Object'] as JSObject).callMethod(
    'defineProperty'.toJS,
    web.window.navigator,
    'userAgent'.toJS,
    {'value': userAgent, 'configurable': true}.jsify(),
  );
  addTearDown(() => web.window.navigator.delete('userAgent'.toJS));
  SharedPreferences.setMockInitialValues({});
  final logger = MixpanelLogger(LogLevel.none);
  Uri? settingsUri;
  final client = MockClient((request) async {
    settingsUri = request.url;
    return http.Response('{"recording":{"is_enabled":true}}', 200);
  });
  addTearDown(client.close);
  final settings = SettingsService(
    token: 'test-token',
    logger: logger,
    storageProvider: SettingsStorageProvider(
      token: 'test-token',
      logger: logger,
    ),
    httpClient: client,
    bundleId: 'test-app',
    buildNumber: '1',
  );
  addTearDown(settings.dispose);
  await settings.fetchRemoteSettings();
  final serializer = PayloadSerializer('test-token');
  addTearDown(serializer.dispose);
  final recordParams = serializer.buildQueryParams(
    Session(
      id: 'test-session',
      startTime: DateTime.utc(2026),
      status: SessionStatus.active,
    ),
    'test-user',
    0,
  );
  expect(settingsUri!.path, '/settings');
  for (final params in [settingsUri!.queryParameters, recordParams]) {
    expect(params['mp_lib'], 'flutter-sr-web');
    expect(params['\$os'], expectedOs);
    expect(params.containsKey('\$os'), expectedOs != null);
  }
}

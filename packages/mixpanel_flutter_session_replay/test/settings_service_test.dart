import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:mixpanel_flutter_session_replay/src/internal/settings/settings_service.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/settings/settings_storage_provider.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/event_trigger.dart';

import 'helpers/fake_http_client.dart';

void main() {
  group('SettingsService', () {
    final testToken = 'test-token-123';
    final testLogger = MixpanelLogger(LogLevel.none);
    late SettingsStorageProvider storageProvider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      storageProvider = SettingsStorageProvider(
        token: testToken,
        logger: testLogger,
      );
    });

    group('checkRecordingEnabled', () {
      test(
        'returns true when server responds with recording enabled',
        () async {
          // GIVEN
          final expectedResult = true;
          final httpClient = createFakeSettingsClient(isEnabled: true);
          final service = SettingsService(
            storageProvider: storageProvider,
            token: testToken,
            logger: MixpanelLogger(LogLevel.none),
            httpClient: httpClient,
          );

          // WHEN
          final result = await service.checkRecordingEnabled();

          // THEN
          expect(result, expectedResult);
        },
      );

      test(
        'returns false when server responds with recording disabled',
        () async {
          // GIVEN
          final expectedResult = false;
          final httpClient = createFakeSettingsClient(isEnabled: false);
          final service = SettingsService(
            storageProvider: storageProvider,
            token: testToken,
            logger: MixpanelLogger(LogLevel.none),
            httpClient: httpClient,
          );

          // WHEN
          final result = await service.checkRecordingEnabled();

          // THEN
          expect(result, expectedResult);
        },
      );

      test('returns cached result on subsequent calls', () async {
        // GIVEN
        var requestCount = 0;
        final httpClient = http_testing.MockClient((request) async {
          requestCount++;
          return http.Response(
            jsonEncode({
              'recording': {'is_enabled': true},
            }),
            200,
          );
        });

        final service = SettingsService(
          storageProvider: storageProvider,
          token: testToken,
          logger: MixpanelLogger(LogLevel.none),
          httpClient: httpClient,
        );

        // WHEN
        await service.checkRecordingEnabled();
        await service.checkRecordingEnabled();
        await service.checkRecordingEnabled();

        // THEN
        expect(requestCount, 1);
      });

      test('defaults to enabled on network error (no cache)', () async {
        // GIVEN - network fails and no disk cache exists
        final expectedResult = true;
        final httpClient = createFailingHttpClient();
        final service = SettingsService(
          storageProvider: storageProvider,
          token: testToken,
          logger: MixpanelLogger(LogLevel.none),
          httpClient: httpClient,
        );

        // WHEN
        final result = await service.checkRecordingEnabled();

        // THEN - defaults to enabled when no cache exists (matches Android/iOS)
        expect(result, expectedResult);
      });

      test('defaults to enabled on non-200 status code (no cache)', () async {
        // GIVEN - server returns error and no disk cache exists
        final expectedResult = true;
        final httpClient = createFakeHttpClient(statusCode: 500);
        final service = SettingsService(
          storageProvider: storageProvider,
          token: testToken,
          logger: MixpanelLogger(LogLevel.none),
          httpClient: httpClient,
        );

        // WHEN
        final result = await service.checkRecordingEnabled();

        // THEN - defaults to enabled when no cache exists (matches Android/iOS)
        expect(result, expectedResult);
      });

      test(
        'defaults to enabled when response omits is_enabled field',
        () async {
          // GIVEN
          final expectedResult = true;
          final httpClient = http_testing.MockClient((request) async {
            return http.Response(jsonEncode({'recording': {}}), 200);
          });

          final service = SettingsService(
            storageProvider: storageProvider,
            token: testToken,
            logger: MixpanelLogger(LogLevel.none),
            httpClient: httpClient,
          );

          // WHEN
          final result = await service.checkRecordingEnabled();

          // THEN
          expect(result, expectedResult);
        },
      );

      test('deduplicates concurrent requests', () async {
        // GIVEN
        var requestCount = 0;
        final completer = Completer<http.Response>();
        final httpClient = http_testing.MockClient((request) {
          requestCount++;
          return completer.future;
        });
        final response = http.Response(
          jsonEncode({
            'recording': {'is_enabled': true},
          }),
          200,
        );

        final service = SettingsService(
          storageProvider: storageProvider,
          token: testToken,
          logger: MixpanelLogger(LogLevel.none),
          httpClient: httpClient,
        );

        // WHEN - launch multiple concurrent checks, then complete the request
        final future = Future.wait([
          service.checkRecordingEnabled(),
          service.checkRecordingEnabled(),
          service.checkRecordingEnabled(),
        ]);
        completer.complete(response);
        final results = await future;

        // THEN - only one network request, all get same result
        expect(requestCount, 1);
        expect(results, [true, true, true]);
      });
    });

    group('fetchRemoteSettings', () {
      test('returns sdk_config when present in response', () async {
        // GIVEN
        final httpClient = http_testing.MockClient((request) async {
          return http.Response(
            jsonEncode({
              'recording': {'is_enabled': true},
              'sdk_config': {
                'config': {'record_sessions_percent': 50.0},
              },
            }),
            200,
          );
        });

        final service = SettingsService(
          storageProvider: storageProvider,
          token: testToken,
          logger: MixpanelLogger(LogLevel.none),
          httpClient: httpClient,
        );

        // WHEN
        final result = await service.fetchRemoteSettings();

        // THEN
        expect(result.isRecordingEnabled, true);
        expect(result.sdkConfig, isNotNull);
        expect(result.sdkConfig!.recordSessionsPercent, 50.0);
        expect(result.isFromCache, false);
      });

      test('returns null sdk_config when not in response', () async {
        // GIVEN
        final httpClient = createFakeSettingsClient(isEnabled: true);
        final service = SettingsService(
          storageProvider: storageProvider,
          token: testToken,
          logger: MixpanelLogger(LogLevel.none),
          httpClient: httpClient,
        );

        // WHEN
        final result = await service.fetchRemoteSettings();

        // THEN
        expect(result.isRecordingEnabled, true);
        expect(result.sdkConfig, isNull);
        expect(result.isFromCache, false);
      });

      test('returns null sdk_config when config is null in wrapper', () async {
        // GIVEN
        final httpClient = http_testing.MockClient((request) async {
          return http.Response(
            jsonEncode({
              'recording': {'is_enabled': true},
              'sdk_config': {'config': null, 'error': 'Not configured'},
            }),
            200,
          );
        });

        final service = SettingsService(
          storageProvider: storageProvider,
          token: testToken,
          logger: MixpanelLogger(LogLevel.none),
          httpClient: httpClient,
        );

        // WHEN
        final result = await service.fetchRemoteSettings();

        // THEN
        expect(result.isRecordingEnabled, true);
        expect(result.sdkConfig, isNull);
      });

      test('returns isFromCache=true on network failure', () async {
        // GIVEN
        final httpClient = createFailingHttpClient();
        final service = SettingsService(
          storageProvider: storageProvider,
          token: testToken,
          logger: MixpanelLogger(LogLevel.none),
          httpClient: httpClient,
        );

        // WHEN
        final result = await service.fetchRemoteSettings();

        // THEN
        expect(result.isFromCache, true);
        expect(result.isRecordingEnabled, true); // default when no cache
        expect(result.sdkConfig, isNull); // no cache
      });

      test('returns recording disabled with error message', () async {
        // GIVEN
        final httpClient = http_testing.MockClient((request) async {
          return http.Response(
            jsonEncode({
              'recording': {
                'is_enabled': false,
                'error': 'Recording disabled by admin',
              },
            }),
            200,
          );
        });

        final service = SettingsService(
          storageProvider: storageProvider,
          token: testToken,
          logger: MixpanelLogger(LogLevel.none),
          httpClient: httpClient,
        );

        // WHEN
        final result = await service.fetchRemoteSettings();

        // THEN
        expect(result.isRecordingEnabled, false);
      });

      test('caches result and returns same on subsequent calls', () async {
        // GIVEN
        var requestCount = 0;
        final httpClient = http_testing.MockClient((request) async {
          requestCount++;
          return http.Response(
            jsonEncode({
              'recording': {'is_enabled': true},
              'sdk_config': {
                'config': {'record_sessions_percent': 75.0},
              },
            }),
            200,
          );
        });

        final service = SettingsService(
          storageProvider: storageProvider,
          token: testToken,
          logger: MixpanelLogger(LogLevel.none),
          httpClient: httpClient,
        );

        // WHEN
        final result1 = await service.fetchRemoteSettings();
        final result2 = await service.fetchRemoteSettings();

        // THEN
        expect(requestCount, 1);
        expect(result1.sdkConfig!.recordSessionsPercent, 75.0);
        expect(result2.sdkConfig!.recordSessionsPercent, 75.0);
      });
    });

    group('remoteState', () {
      test('is pending before any check', () {
        // GIVEN
        final service = SettingsService(
          storageProvider: storageProvider,
          token: testToken,
          logger: MixpanelLogger(LogLevel.none),
          httpClient: createFakeSettingsClient(isEnabled: true),
        );

        // THEN
        expect(service.remoteState, RemoteEnablementState.pending);
      });

      test(
        'is enabled after successful check with recording enabled',
        () async {
          // GIVEN
          final service = SettingsService(
            storageProvider: storageProvider,
            token: testToken,
            logger: MixpanelLogger(LogLevel.none),
            httpClient: createFakeSettingsClient(isEnabled: true),
          );

          // WHEN
          await service.fetchRemoteSettings();

          // THEN
          expect(service.remoteState, RemoteEnablementState.enabled);
        },
      );

      test(
        'is disabled after successful check with recording disabled',
        () async {
          // GIVEN
          final service = SettingsService(
            storageProvider: storageProvider,
            token: testToken,
            logger: MixpanelLogger(LogLevel.none),
            httpClient: createFakeSettingsClient(isEnabled: false),
          );

          // WHEN
          await service.fetchRemoteSettings();

          // THEN
          expect(service.remoteState, RemoteEnablementState.disabled);
        },
      );
    });

    group('SdkConfig', () {
      test('parses record_sessions_percent from JSON', () {
        // GIVEN
        final json = {'record_sessions_percent': 42.5};

        // WHEN
        final config = SdkConfig.fromJson(json);

        // THEN
        expect(config.recordSessionsPercent, 42.5);
      });

      test('handles missing record_sessions_percent', () {
        // GIVEN
        final json = <String, dynamic>{};

        // WHEN
        final config = SdkConfig.fromJson(json);

        // THEN
        expect(config.recordSessionsPercent, isNull);
      });

      test('handles integer value for record_sessions_percent', () {
        // GIVEN
        final json = {'record_sessions_percent': 100};

        // WHEN
        final config = SdkConfig.fromJson(json);

        // THEN
        expect(config.recordSessionsPercent, 100.0);
      });

      test('round-trips through toJson/fromJson', () {
        // GIVEN
        final original = SdkConfig(recordSessionsPercent: 55.5);

        // WHEN
        final json = original.toJson();
        final restored = SdkConfig.fromJson(json);

        // THEN
        expect(restored.recordSessionsPercent, 55.5);
      });

      group('recording_event_triggers', () {
        test('parses event-name-keyed map of triggers from JSON', () {
          // GIVEN
          final json = {
            'recording_event_triggers': {
              'Login': {'percentage': 100.0},
              'Purchase': {
                'percentage': 50.0,
                'property_filters': {
                  '===': [
                    {'var': '\$city'},
                    'NYC',
                  ],
                },
              },
            },
          };

          // WHEN
          final config = SdkConfig.fromJson(json);

          // THEN
          expect(config.recordingEventTriggers, isNotNull);
          expect(config.recordingEventTriggers!.length, 2);
          expect(config.recordingEventTriggers!['Login']!.percentage, 100.0);
          expect(
            config.recordingEventTriggers!['Login']!.propertyFilters,
            isNull,
          );
          expect(config.recordingEventTriggers!['Purchase']!.percentage, 50.0);
          expect(
            config.recordingEventTriggers!['Purchase']!.propertyFilters,
            isNotNull,
          );
        });

        test('treats missing recording_event_triggers as null', () {
          final config = SdkConfig.fromJson(const {
            'record_sessions_percent': 100.0,
          });
          expect(config.recordingEventTriggers, isNull);
        });

        test('treats empty recording_event_triggers as null', () {
          final config = SdkConfig.fromJson(const {
            'recording_event_triggers': <String, dynamic>{},
          });
          expect(config.recordingEventTriggers, isNull);
        });

        test(
          'round-trips a populated triggers map through toJson/fromJson',
          () {
            // GIVEN
            final original = SdkConfig(
              recordSessionsPercent: 25.0,
              recordingEventTriggers: const {
                'Login': EventTrigger(percentage: 100),
                'Filtered': EventTrigger(
                  percentage: 50,
                  propertyFilters: {
                    '===': [
                      {'var': 'tier'},
                      'premium',
                    ],
                  },
                ),
              },
            );

            // WHEN
            final restored = SdkConfig.fromJson(original.toJson());

            // THEN
            expect(restored.recordSessionsPercent, 25.0);
            expect(restored.recordingEventTriggers!.length, 2);
            expect(
              restored.recordingEventTriggers!['Login']!.percentage,
              100.0,
            );
            expect(
              restored.recordingEventTriggers!['Filtered']!.propertyFilters,
              isNotNull,
            );
          },
        );

        test('coerces integer percentage to double', () {
          final config = SdkConfig.fromJson(const {
            'recording_event_triggers': {
              'X': {'percentage': 75},
            },
          });
          expect(config.recordingEventTriggers!['X']!.percentage, 75.0);
        });
      });
    });

    test('sends correct endpoint, auth header, and query parameters', () async {
      // GIVEN
      final expectedCredentials = base64Encode(utf8.encode('$testToken:'));
      final expectedAuthHeader = 'Basic $expectedCredentials';

      final recorder = createRecordingHttpClient(
        statusCode: 200,
        body: jsonEncode({
          'recording': {'is_enabled': true},
        }),
      );

      final service = SettingsService(
        storageProvider: storageProvider,
        token: testToken,
        logger: MixpanelLogger(LogLevel.none),
        httpClient: recorder.client,
      );

      // WHEN
      await service.checkRecordingEnabled();

      // THEN
      expect(recorder.requests.length, 1);
      final request = recorder.requests[0];
      final uri = request.url;

      expect(uri.host, 'api.mixpanel.com');
      expect(uri.path, '/settings');
      expect(request.headers['Authorization'], expectedAuthHeader);
      expect(uri.queryParameters['recording'], '1');
      expect(uri.queryParameters['sdk_config'], '1');
      expect(uri.queryParameters['mp_lib'], 'flutter-sr');
      expect(uri.queryParameters['\$lib_version'], endsWith('-flutter'));
      expect(uri.queryParameters['\$os'], anyOf('Android', 'iOS', 'Mac OS X'));
    });

    test('uses custom serverUrl when configured', () async {
      // GIVEN
      final recorder = createRecordingHttpClient(
        statusCode: 200,
        body: jsonEncode({
          'recording': {'is_enabled': true},
        }),
      );

      final service = SettingsService(
        storageProvider: storageProvider,
        token: testToken,
        logger: MixpanelLogger(LogLevel.none),
        httpClient: recorder.client,
        serverUrl: 'https://api-eu.mixpanel.com',
      );

      // WHEN
      await service.checkRecordingEnabled();

      // THEN
      final uri = recorder.requests.single.url;
      expect(uri.host, 'api-eu.mixpanel.com');
      expect(uri.path, '/settings');
    });

    test(
      'preserves a path on the serverUrl when building the settings endpoint',
      () async {
        // KEY behavior — matches Android, diverges from iOS. The settings call
        // must hit `<base>/<path>/settings`, not have the path dropped.
        // GIVEN
        final recorder = createRecordingHttpClient(
          statusCode: 200,
          body: jsonEncode({
            'recording': {'is_enabled': true},
          }),
        );

        final service = SettingsService(
          storageProvider: storageProvider,
          token: testToken,
          logger: MixpanelLogger(LogLevel.none),
          httpClient: recorder.client,
          serverUrl: 'https://proxy.example.com/mp',
        );

        // WHEN
        await service.checkRecordingEnabled();

        // THEN
        final uri = recorder.requests.single.url;
        expect(uri.host, 'proxy.example.com');
        expect(uri.path, '/mp/settings');
      },
    );
  });
}

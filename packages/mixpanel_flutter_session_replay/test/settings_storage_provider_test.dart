import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/settings/settings_storage_provider.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsStorageProvider', () {
    final testToken = 'test-token';
    final enabledKey = 'mp_sr_flutter_${testToken}_enabled';
    final sdkConfigKey = 'mp_sr_flutter_${testToken}_sdk_config';

    SettingsStorageProvider createProvider({
      Map<String, Object> initialData = const {},
    }) {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(initialData);
      return SettingsStorageProvider(
        token: testToken,
        logger: MixpanelLogger(LogLevel.none),
      );
    }

    group('recording state', () {
      test('defaults to true when no cache exists', () async {
        // GIVEN
        final provider = createProvider();

        // WHEN
        final result = await provider.getRecordingEnabled();

        // THEN
        expect(result, true);
      });

      test('returns false when cached as disabled', () async {
        // GIVEN
        final provider = createProvider(initialData: {enabledKey: false});

        // WHEN
        final result = await provider.getRecordingEnabled();

        // THEN
        expect(result, false);
      });

      test('returns true when cached as enabled', () async {
        // GIVEN
        final provider = createProvider(initialData: {enabledKey: true});

        // WHEN
        final result = await provider.getRecordingEnabled();

        // THEN
        expect(result, true);
      });
    });

    group('SDK config', () {
      test('returns null when no cache exists', () async {
        // GIVEN
        final provider = createProvider();

        // WHEN
        final result = await provider.getSdkConfig();

        // THEN
        expect(result, isNull);
      });

      test('returns cached config when present', () async {
        // GIVEN
        final configJson = jsonEncode({'record_sessions_percent': 42.5});
        final provider = createProvider(
          initialData: {sdkConfigKey: configJson},
        );

        // WHEN
        final result = await provider.getSdkConfig();

        // THEN
        expect(result, isNotNull);
        expect(result!.recordSessionsPercent, 42.5);
      });

      test('returns null for invalid JSON in cache', () async {
        // GIVEN
        final provider = createProvider(
          initialData: {sdkConfigKey: 'not-valid-json'},
        );

        // WHEN
        final result = await provider.getSdkConfig();

        // THEN
        expect(result, isNull);
      });
    });

    group('getCachedSettingsResult', () {
      test('returns defaults when no cache exists', () async {
        // GIVEN
        final provider = createProvider();

        // WHEN
        final result = await provider.getCachedSettingsResult();

        // THEN
        expect(result.isRecordingEnabled, true);
        expect(result.sdkConfig, isNull);
        expect(result.isFromCache, true);
      });

      test('returns cached values when both are stored', () async {
        // GIVEN
        final configJson = jsonEncode({'record_sessions_percent': 75.0});
        final provider = createProvider(
          initialData: {enabledKey: false, sdkConfigKey: configJson},
        );

        // WHEN
        final result = await provider.getCachedSettingsResult();

        // THEN
        expect(result.isRecordingEnabled, false);
        expect(result.sdkConfig, isNotNull);
        expect(result.sdkConfig!.recordSessionsPercent, 75.0);
        expect(result.isFromCache, true);
      });

      test(
        'returns partial cache when only recording state is stored',
        () async {
          // GIVEN
          final provider = createProvider(initialData: {enabledKey: false});

          // WHEN
          final result = await provider.getCachedSettingsResult();

          // THEN
          expect(result.isRecordingEnabled, false);
          expect(result.sdkConfig, isNull);
          expect(result.isFromCache, true);
        },
      );
    });

    test('uses token-scoped keys for isolation', () async {
      // GIVEN - cache populated for token-a only
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
            'mp_sr_flutter_token-a_enabled': false,
            'mp_sr_flutter_token-a_sdk_config': jsonEncode({
              'record_sessions_percent': 25.0,
            }),
          });

      final providerA = SettingsStorageProvider(
        token: 'token-a',
        logger: MixpanelLogger(LogLevel.none),
      );
      final providerB = SettingsStorageProvider(
        token: 'token-b',
        logger: MixpanelLogger(LogLevel.none),
      );

      // THEN - provider B is unaffected by provider A's cache
      expect(await providerA.getRecordingEnabled(), false);
      expect(await providerB.getRecordingEnabled(), true);
      expect((await providerA.getSdkConfig())?.recordSessionsPercent, 25.0);
      expect(await providerB.getSdkConfig(), isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/endpoints.dart';

void main() {
  group('DataResidency', () {
    test('US constant matches Mixpanel US base URL', () {
      expect(DataResidency.us, 'https://api.mixpanel.com');
    });

    test('EU constant matches Mixpanel EU base URL', () {
      expect(DataResidency.eu, 'https://api-eu.mixpanel.com');
    });

    test('India constant matches Mixpanel India base URL', () {
      expect(DataResidency.india, 'https://api-in.mixpanel.com');
    });

    test('all constants are HTTPS and have no path component', () {
      for (final url in [
        DataResidency.us,
        DataResidency.eu,
        DataResidency.india,
      ]) {
        expect(url, startsWith('https://'));
        expect(url, isNot(endsWith('/')));
        expect(Uri.parse(url).path, isEmpty);
      }
    });
  });

  group('EndPoints', () {
    test('defaultBaseUrl is US data residency', () {
      expect(EndPoints.defaultBaseUrl, DataResidency.us);
    });

    group('record', () {
      test('appends /record to US base URL', () {
        expect(
          EndPoints.record(DataResidency.us),
          'https://api.mixpanel.com/record',
        );
      });

      test('appends /record to EU base URL', () {
        expect(
          EndPoints.record(DataResidency.eu),
          'https://api-eu.mixpanel.com/record',
        );
      });

      test('appends /record to India base URL', () {
        expect(
          EndPoints.record(DataResidency.india),
          'https://api-in.mixpanel.com/record',
        );
      });

      test('trims a single trailing slash before appending /record', () {
        expect(
          EndPoints.record('https://api-eu.mixpanel.com/'),
          'https://api-eu.mixpanel.com/record',
        );
      });

      test('trims multiple trailing slashes before appending /record', () {
        expect(
          EndPoints.record('https://api-eu.mixpanel.com///'),
          'https://api-eu.mixpanel.com/record',
        );
      });

      test('preserves a path component on the base URL', () {
        // KEY behavior — matches Android, diverges from iOS. Proxy URLs that
        // include a path must be preserved, not dropped.
        expect(
          EndPoints.record('https://proxy.example.com/mp'),
          'https://proxy.example.com/mp/record',
        );
      });

      test('preserves a path with a trailing slash on the base URL', () {
        expect(
          EndPoints.record('https://proxy.example.com/mp/'),
          'https://proxy.example.com/mp/record',
        );
      });

      test('preserves nested paths on the base URL', () {
        expect(
          EndPoints.record('https://proxy.example.com/team/mp/'),
          'https://proxy.example.com/team/mp/record',
        );
      });
    });

    group('settings', () {
      test('appends /settings to US base URL', () {
        expect(
          EndPoints.settings(DataResidency.us),
          'https://api.mixpanel.com/settings',
        );
      });

      test('appends /settings to EU base URL', () {
        expect(
          EndPoints.settings(DataResidency.eu),
          'https://api-eu.mixpanel.com/settings',
        );
      });

      test('appends /settings to India base URL', () {
        expect(
          EndPoints.settings(DataResidency.india),
          'https://api-in.mixpanel.com/settings',
        );
      });

      test('trims a trailing slash before appending /settings', () {
        expect(
          EndPoints.settings('https://api-eu.mixpanel.com/'),
          'https://api-eu.mixpanel.com/settings',
        );
      });

      test('preserves a path component on the base URL', () {
        expect(
          EndPoints.settings('https://proxy.example.com/mp'),
          'https://proxy.example.com/mp/settings',
        );
      });

      test('preserves a path with a trailing slash on the base URL', () {
        expect(
          EndPoints.settings('https://proxy.example.com/mp/'),
          'https://proxy.example.com/mp/settings',
        );
      });
    });
  });

  group('validateServerUrl', () {
    test('accepts US data residency URL', () {
      final result = validateServerUrl(DataResidency.us);
      expect(result, isA<ServerUrlValid>());
      expect((result as ServerUrlValid).trimmedUrl, DataResidency.us);
    });

    test('accepts EU data residency URL', () {
      final result = validateServerUrl(DataResidency.eu);
      expect(result, isA<ServerUrlValid>());
    });

    test('accepts India data residency URL', () {
      final result = validateServerUrl(DataResidency.india);
      expect(result, isA<ServerUrlValid>());
    });

    test('accepts a custom https URL', () {
      final result = validateServerUrl('https://custom.example.com');
      expect(result, isA<ServerUrlValid>());
    });

    test('accepts a custom https URL that includes a path', () {
      // KEY behavior — Android allows paths on the base URL; iOS rejects them.
      // We match Android.
      final result = validateServerUrl('https://proxy.example.com/mp');
      expect(result, isA<ServerUrlValid>());
      expect(
        (result as ServerUrlValid).trimmedUrl,
        'https://proxy.example.com/mp',
      );
    });

    test('trims surrounding whitespace', () {
      final result = validateServerUrl('  https://api-eu.mixpanel.com  ');
      expect(result, isA<ServerUrlValid>());
      expect(
        (result as ServerUrlValid).trimmedUrl,
        'https://api-eu.mixpanel.com',
      );
    });

    test('rejects an empty string', () {
      final result = validateServerUrl('');
      expect(result, isA<ServerUrlInvalid>());
      expect(
        (result as ServerUrlInvalid).message,
        contains('must start with https://'),
      );
    });

    test('rejects a whitespace-only string', () {
      final result = validateServerUrl('   ');
      expect(result, isA<ServerUrlInvalid>());
    });

    test('rejects an http:// URL', () {
      final result = validateServerUrl('http://api.mixpanel.com');
      expect(result, isA<ServerUrlInvalid>());
      expect(
        (result as ServerUrlInvalid).message,
        contains('must start with https://'),
      );
    });

    test('rejects an ftp:// URL', () {
      final result = validateServerUrl('ftp://api.mixpanel.com');
      expect(result, isA<ServerUrlInvalid>());
    });

    test('rejects a host-only string without a scheme', () {
      final result = validateServerUrl('api.mixpanel.com');
      expect(result, isA<ServerUrlInvalid>());
    });

    test('rejects a malformed URL', () {
      final result = validateServerUrl('https://');
      expect(result, isA<ServerUrlInvalid>());
    });
  });
}

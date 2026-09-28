import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/options_validation.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';

void main() {
  final logger = MixpanelLogger(LogLevel.none);

  group('capPlatformOptions', () {
    test('keeps timings within 24 hours unchanged', () {
      // GIVEN the default platform options
      const options = PlatformOptions();

      // WHEN the options are capped
      final capped = capPlatformOptions(options, logger);

      // THEN the configured values pass through
      expect(capped.mobile.wifiOnly, isTrue);
      expect(capped.mobile.onBackground, ReplayBackgroundBehavior.stop);
      expect(capped.web.idleTimeout, const Duration(minutes: 30));
      expect(capped.web.maxSessionDuration, const Duration(hours: 24));
      expect(
        (capped.web.onBackground as ReplayBackgroundPauseBehavior).idleTimeout,
        const Duration(minutes: 30),
      );
    });

    test('caps every timing above 24 hours', () {
      // GIVEN web and mobile timings longer than mixpanel-js allows
      const days = Duration(days: 30);
      const options = PlatformOptions(
        mobile: MobileOptions(
          wifiOnly: false,
          onBackground: ReplayBackgroundBehavior.pause(idleTimeout: days),
        ),
        web: WebOptions(
          idleTimeout: days,
          maxSessionDuration: days,
          onBackground: ReplayBackgroundBehavior.pause(idleTimeout: days),
        ),
      );

      // WHEN the options are capped
      final capped = capPlatformOptions(options, logger);

      // THEN each duration is lowered to the 24-hour maximum and the other
      // settings are carried over
      const cap = Duration(hours: 24);
      expect(capped.web.idleTimeout, cap);
      expect(capped.web.maxSessionDuration, cap);
      expect(
        (capped.mobile.onBackground as ReplayBackgroundPauseBehavior)
            .idleTimeout,
        cap,
      );
      expect(
        (capped.web.onBackground as ReplayBackgroundPauseBehavior).idleTimeout,
        cap,
      );
      expect(capped.mobile.wifiOnly, isFalse);
    });
  });
}

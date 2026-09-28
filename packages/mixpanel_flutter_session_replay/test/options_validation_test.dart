import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/options_validation.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';

void main() {
  final logger = MixpanelLogger(LogLevel.none);

  group('resolvePlatformTimings', () {
    test('keeps timings within 24 hours unchanged', () {
      // GIVEN the default platform options
      const options = PlatformOptions();

      // WHEN the timings are resolved
      final timings = resolvePlatformTimings(options, logger);

      // THEN the configured values pass through
      expect(timings.webIdleTimeout, const Duration(minutes: 30));
      expect(timings.webMaxSessionDuration, const Duration(hours: 24));
      expect(timings.mobileBackgroundBehavior, ReplayBackgroundBehavior.stop);
      expect(
        (timings.webBackgroundBehavior as ReplayBackgroundPauseBehavior)
            .idleTimeout,
        const Duration(minutes: 30),
      );
    });

    test('caps every timing above 24 hours', () {
      // GIVEN web and mobile timings longer than mixpanel-js allows
      const days = Duration(days: 30);
      const options = PlatformOptions(
        mobile: MobileOptions(
          onBackground: ReplayBackgroundBehavior.pause(idleTimeout: days),
        ),
        web: WebOptions(
          idleTimeout: days,
          maxSessionDuration: days,
          onBackground: ReplayBackgroundBehavior.pause(idleTimeout: days),
        ),
      );

      // WHEN the timings are resolved
      final timings = resolvePlatformTimings(options, logger);

      // THEN each is lowered to the 24-hour maximum
      const cap = Duration(hours: 24);
      expect(timings.webIdleTimeout, cap);
      expect(timings.webMaxSessionDuration, cap);
      expect(
        (timings.mobileBackgroundBehavior as ReplayBackgroundPauseBehavior)
            .idleTimeout,
        cap,
      );
      expect(
        (timings.webBackgroundBehavior as ReplayBackgroundPauseBehavior)
            .idleTimeout,
        cap,
      );
    });
  });
}

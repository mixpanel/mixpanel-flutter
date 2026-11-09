import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session/recording_limits.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';

void main() {
  final logger = MixpanelLogger(LogLevel.none);

  group('capRecordingDuration', () {
    test('keeps durations up to 24 hours', () {
      // GIVEN durations at or below the maximum
      for (final duration in [
        const Duration(minutes: 30),
        maxRecordingDuration,
      ]) {
        // WHEN capped
        final capped = capRecordingDuration(
          duration,
          name: 'test',
          logger: logger,
        );

        // THEN they are unchanged
        expect(capped, duration);
      }
    });

    test('caps durations above 24 hours', () {
      // GIVEN a duration past the browser timer ceiling
      const duration = Duration(days: 30);

      // WHEN capped
      final capped = capRecordingDuration(
        duration,
        name: 'test',
        logger: logger,
      );

      // THEN it is lowered to the 24-hour maximum
      expect(capped, const Duration(hours: 24));
    });
  });
}

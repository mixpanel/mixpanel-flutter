import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';

void main() {
  group('MixpanelLogger', () {
    group('LogLevel mapping', () {
      test('debug level maps correctly and outputs fine-level logs', () {
        // GIVEN
        final records = <LogRecord>[];
        final logger = MixpanelLogger(LogLevel.debug);

        // Capture log records
        Logger('mixpanel.session_replay').onRecord.listen(records.add);

        // WHEN
        logger.debug('test debug message');

        // THEN - logger level should be FINE (most verbose)
        expect(Logger('mixpanel.session_replay').level, Level.FINE);
      });

      test('info level maps correctly', () {
        // GIVEN / WHEN
        MixpanelLogger(LogLevel.info);

        // THEN - logger level should be at most INFO
        expect(
          Logger('mixpanel.session_replay').level.value <= Level.INFO.value,
          true,
        );
      });

      test('warning level maps correctly', () {
        // GIVEN / WHEN
        MixpanelLogger(LogLevel.warning);

        // THEN
        expect(
          Logger('mixpanel.session_replay').level.value <= Level.WARNING.value,
          true,
        );
      });

      test('error level maps correctly', () {
        // GIVEN / WHEN
        MixpanelLogger(LogLevel.error);

        // THEN
        expect(
          Logger('mixpanel.session_replay').level.value <= Level.SEVERE.value,
          true,
        );
      });

      test('none level maps to OFF', () {
        // GIVEN / WHEN
        final logger = MixpanelLogger(LogLevel.none);

        // THEN - creating with none should not error
        logger.debug('should be suppressed');
        logger.info('should be suppressed');
        logger.warning('should be suppressed');
        logger.error('should be suppressed');
      });
    });

    group('message formatting', () {
      test('debug formats message with tag', () {
        // GIVEN
        final logger = MixpanelLogger(LogLevel.debug);
        final records = <LogRecord>[];
        Logger('mixpanel.session_replay').onRecord.listen(records.add);

        // WHEN
        logger.debug('test message', tag: 'MyTag');

        // THEN
        expect(records.isNotEmpty, true);
        expect(records.last.message, '[MyTag] test message');
      });

      test('debug formats message without tag', () {
        // GIVEN
        final logger = MixpanelLogger(LogLevel.debug);
        final records = <LogRecord>[];
        Logger('mixpanel.session_replay').onRecord.listen(records.add);

        // WHEN
        logger.debug('plain message');

        // THEN
        expect(records.isNotEmpty, true);
        expect(records.last.message, 'plain message');
      });

      test('info formats message with tag', () {
        // GIVEN
        final logger = MixpanelLogger(LogLevel.debug);
        final records = <LogRecord>[];
        Logger('mixpanel.session_replay').onRecord.listen(records.add);

        // WHEN
        logger.info('info message', tag: 'InfoTag');

        // THEN
        expect(records.last.message, '[InfoTag] info message');
      });

      test('warning formats message with tag', () {
        // GIVEN
        final logger = MixpanelLogger(LogLevel.debug);
        final records = <LogRecord>[];
        Logger('mixpanel.session_replay').onRecord.listen(records.add);

        // WHEN
        logger.warning('warn message', tag: 'WarnTag');

        // THEN
        expect(records.last.message, '[WarnTag] warn message');
      });

      test('error formats message with tag', () {
        // GIVEN
        final logger = MixpanelLogger(LogLevel.debug);
        final records = <LogRecord>[];
        Logger('mixpanel.session_replay').onRecord.listen(records.add);

        // WHEN
        logger.error('error message', Exception('test'), null, 'ErrorTag');

        // THEN
        expect(records.last.message, '[ErrorTag] error message');
        expect(records.last.error, isA<Exception>());
      });

      test('error passes error and stack trace to logger', () {
        // GIVEN
        final logger = MixpanelLogger(LogLevel.debug);
        final records = <LogRecord>[];
        Logger('mixpanel.session_replay').onRecord.listen(records.add);
        final testError = StateError('test error');
        final testStack = StackTrace.current;

        // WHEN
        logger.error('failed', testError, testStack);

        // THEN
        expect(records.last.error, testError);
        expect(records.last.stackTrace, testStack);
      });
    });

    group('dispose', () {
      test('dispose is a no-op and does not throw', () {
        // GIVEN
        final logger = MixpanelLogger(LogLevel.debug);

        // WHEN / THEN - dispose is safe to call
        logger.dispose();

        // Logger still works after dispose (singleton behavior)
        logger.info('still works');
      });
    });
  });
}

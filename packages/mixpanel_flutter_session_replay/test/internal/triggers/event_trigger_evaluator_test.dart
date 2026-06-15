import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/triggers/event_trigger_evaluator.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/event_trigger.dart';

void main() {
  final logger = MixpanelLogger(LogLevel.none);

  EventTriggerEvaluator evaluatorFor(Map<String, EventTrigger> triggers) =>
      EventTriggerEvaluator(triggers, logger);

  group('EventTriggerEvaluator', () {
    test('returns null when no trigger registered for event name', () {
      final eval = evaluatorFor({'Login': const EventTrigger(percentage: 100)});
      expect(eval.shouldStartRecording('Logout', const {}), isNull);
    });

    test('returns percentage when trigger has no propertyFilters', () {
      final eval = evaluatorFor({'Login': const EventTrigger(percentage: 75)});
      expect(eval.shouldStartRecording('Login', const {}), 75);
    });

    test('returns percentage when propertyFilters evaluate to true', () {
      final eval = evaluatorFor({
        'Purchase': const EventTrigger(
          percentage: 50,
          propertyFilters: {
            '===': [
              {'var': '\$city'},
              'NYC',
            ],
          },
        ),
      });
      expect(eval.shouldStartRecording('Purchase', {'\$city': 'NYC'}), 50);
    });

    test('returns null when propertyFilters evaluate to false', () {
      final eval = evaluatorFor({
        'Purchase': const EventTrigger(
          percentage: 50,
          propertyFilters: {
            '===': [
              {'var': '\$city'},
              'NYC',
            ],
          },
        ),
      });
      expect(eval.shouldStartRecording('Purchase', {'\$city': 'LA'}), isNull);
    });

    test('null event properties treated as empty map for filter eval', () {
      // Rule references {"var": "x"}; with no data, var returns null;
      // strict-equality of null with "y" throws TypeMismatch → fail closed.
      final eval = evaluatorFor({
        'X': const EventTrigger(
          percentage: 100,
          propertyFilters: {
            '===': [
              {'var': 'x'},
              'y',
            ],
          },
        ),
      });
      expect(eval.shouldStartRecording('X', null), isNull);
    });

    test('JSONLogic parse error returns null (fail closed)', () {
      // Multi-key object as expression body is a parse error in JSONLogic.
      final eval = evaluatorFor({
        'Bad': const EventTrigger(
          percentage: 100,
          propertyFilters: {
            '===': [1, 1],
            '!==': [1, 2],
          },
        ),
      });
      expect(eval.shouldStartRecording('Bad', const {}), isNull);
    });

    test('JSONLogic evaluation error returns null (fail closed)', () {
      // Unsupported operator at parse time still surfaces as fail-closed
      // because EventTriggerEvaluator catches it.
      final eval = evaluatorFor({
        'Bad': const EventTrigger(
          percentage: 100,
          propertyFilters: {
            '+': [1, 2],
          },
        ),
      });
      expect(eval.shouldStartRecording('Bad', const {}), isNull);
    });

    test('negative percentage rejected', () {
      final eval = evaluatorFor({'X': const EventTrigger(percentage: -1)});
      expect(eval.shouldStartRecording('X', const {}), isNull);
    });

    test('percentage > 100 rejected', () {
      final eval = evaluatorFor({'X': const EventTrigger(percentage: 101)});
      expect(eval.shouldStartRecording('X', const {}), isNull);
    });

    test('NaN percentage rejected', () {
      final eval = evaluatorFor({'X': EventTrigger(percentage: double.nan)});
      expect(eval.shouldStartRecording('X', const {}), isNull);
    });

    test('0 and 100 are valid boundary percentages', () {
      final eval = evaluatorFor({
        'Zero': const EventTrigger(percentage: 0),
        'Hundred': const EventTrigger(percentage: 100),
      });
      expect(eval.shouldStartRecording('Zero', const {}), 0);
      expect(eval.shouldStartRecording('Hundred', const {}), 100);
    });

    test('JSONLogic result of non-bool (e.g. number) is treated as false', () {
      // {"var": "x"} resolves to a number; not a bool → fail closed.
      final eval = evaluatorFor({
        'X': const EventTrigger(percentage: 100, propertyFilters: {'var': 'x'}),
      });
      expect(eval.shouldStartRecording('X', {'x': 42}), isNull);
    });
  });
}

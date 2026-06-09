import 'package:test/test.dart';
import 'package:mixpanel_flutter_common/mixpanel_flutter_common.dart';

/// Tests for defensive limits added to guard against malicious server-supplied
/// rules: depth bound (stack-overflow DoS), error-message truncation (log
/// blowup), and correctness of the allocation-free and/or/in walks.
void main() {
  group('depth limit (stack-overflow defense)', () {
    String nested(int depth) {
      // Build {"!==":[{"!==":[ ... {"!==":[1,2]} ... ]}]} N levels deep.
      final open = '{"!==":[' * depth;
      final close = ',2]}' * depth;
      // Innermost left operand must be a literal — 1 with the trailing ,2.
      return '$open${1.toString()}$close';
    }

    test('parses successfully at exactly maxDepth', () {
      // A tree at exactly the limit must parse — we only care about the
      // parser's depth guard here, so evaluation is intentionally skipped
      // (the !== chain produces a bool that wouldn't satisfy the outer
      // !== against a number).
      expect(
        () => JsonLogicParser.parse(nested(JsonLogicParser.maxDepth)),
        returnsNormally,
      );
    });

    test('throws InvalidExpressionException when depth exceeds maxDepth', () {
      expect(
        () => JsonLogicParser.parse(nested(JsonLogicParser.maxDepth + 5)),
        throwsA(
          isA<InvalidExpressionException>().having(
            (e) => e.message,
            'message',
            contains('nesting depth exceeds maximum'),
          ),
        ),
      );
    });

    test('depth check applies through array operands', () {
      // and/or wrap their operands in a list — make sure the depth counter
      // ticks through that path too.
      final operand = nested(JsonLogicParser.maxDepth);
      expect(
        () => JsonLogicParser.parse('{"and":[$operand]}'),
        throwsA(isA<InvalidExpressionException>()),
      );
    });

    test('evaluator survives at maxDepth (no stack overflow)', () {
      // Chain `or` so each level returns a bool that the outer `or` accepts.
      // Confirms the evaluator can actually walk a tree at the parser limit.
      final open = '{"or":[' * (JsonLogicParser.maxDepth - 1);
      final close = ']}' * (JsonLogicParser.maxDepth - 1);
      final rule = '$open{"===":[1,1]}$close';
      expect(
        JsonLogicEvaluator.evaluate(JsonLogicParser.parse(rule), const {}),
        isTrue,
      );
    });
  });

  group('error message truncation (log-blowup defense)', () {
    test('malformed JSON message is bounded', () {
      final huge = '{' * 50000; // 50KB of garbage
      try {
        JsonLogicParser.parse(huge);
        fail('expected exception');
      } on InvalidExpressionException catch (e) {
        // Echo capped to ~200 chars plus the surrounding message text.
        // Message format is bounded; assert it is dramatically smaller than
        // the input.
        expect(e.message.length, lessThan(500));
        expect(e.message, contains('...'));
      }
    });

    test('non-object input message is bounded', () {
      final huge = '"${'a' * 50000}"'; // 50KB string literal
      try {
        JsonLogicParser.parse(huge);
        fail('expected exception');
      } on InvalidExpressionException catch (e) {
        expect(e.message.length, lessThan(500));
        expect(e.message, contains('...'));
      }
    });

    test('multi-key object message is bounded', () {
      // Build a rule with many keys so the rendered key list would be huge.
      final keys = List.generate(5000, (i) => '"k$i":1').join(',');
      try {
        JsonLogicParser.parse('{$keys}');
        fail('expected exception');
      } on InvalidExpressionException catch (e) {
        expect(e.message.length, lessThan(500));
        expect(e.message, contains('...'));
      }
    });

    test('short input is not truncated', () {
      try {
        JsonLogicParser.parse('not json');
        fail('expected exception');
      } on InvalidExpressionException catch (e) {
        expect(e.message, contains('not json'));
        expect(e.message, isNot(contains('...')));
      }
    });
  });

  group('allocation-free and/or/in (memory defense)', () {
    // These are correctness tests for the rewritten loops — they ensure the
    // type-safety contract (evaluate ALL operands) is preserved after
    // dropping the intermediate List materialization.

    test('and: late type error still surfaces after early false', () {
      expect(
        () => JsonLogicEvaluator.evaluate(
          JsonLogicParser.parse(
            '{"and":[{"===":[1,2]}, {"===":[1, "1"]}, {"===":[1,1]}]}',
          ),
          const {},
        ),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('or: late type error still surfaces after early true', () {
      expect(
        () => JsonLogicEvaluator.evaluate(
          JsonLogicParser.parse(
            '{"or":[{"===":[1,1]}, {"===":[1, "1"]}, {"===":[1,2]}]}',
          ),
          const {},
        ),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('in (array): late non-string element still surfaces after match', () {
      expect(
        () => JsonLogicEvaluator.evaluate(
          JsonLogicParser.parse('{"in":["a", ["a", "b", 1]]}'),
          const {},
        ),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('and: large operand list evaluates correctly', () {
      // 10k operands, all true. Verifies the loop terminates and we don't
      // blow the stack/heap on a moderately large input.
      final operands = List.generate(10000, (_) => '{"===":[1,1]}').join(',');
      expect(
        JsonLogicEvaluator.evaluate(
          JsonLogicParser.parse('{"and":[$operands]}'),
          const {},
        ),
        isTrue,
      );
    });

    test('or: large operand list with single trailing true returns true', () {
      final operands = [
        ...List.generate(9999, (_) => '{"===":[1,2]}'),
        '{"===":[1,1]}',
      ].join(',');
      expect(
        JsonLogicEvaluator.evaluate(
          JsonLogicParser.parse('{"or":[$operands]}'),
          const {},
        ),
        isTrue,
      );
    });

    test('in (array): large haystack with trailing match returns true', () {
      final elements = [
        ...List.generate(9999, (i) => '"item$i"'),
        '"target"',
      ].join(',');
      expect(
        JsonLogicEvaluator.evaluate(
          JsonLogicParser.parse('{"in":["target", [$elements]]}'),
          const {},
        ),
        isTrue,
      );
    });
  });
}

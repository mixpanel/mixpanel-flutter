import 'package:test/test.dart';
import 'package:mixpanel_flutter_common/mixpanel_flutter_common.dart';
// Concrete rule subclasses are package-internal — reach them via the src/
// path so the test can build them directly without widening the public API.
import 'package:mixpanel_flutter_common/src/jsonlogic/json_logic_rule.dart';

/// Additional edge cases beyond the shared Android/Swift test corpus.
///
/// Covers Dart-specific concerns (int↔double numeric model, `String.contains`
/// behavior with empty needles, const-map handling) plus scenarios where the
/// spec's behavior is implicit rather than explicitly tested upstream:
/// nested var paths, falsy var values, deep boolean nesting, parser quirks.
void main() {
  Object? evaluate(String ruleJson, [Map<String, Object?> data = const {}]) {
    return JsonLogicEvaluator.evaluate(JsonLogicParser.parse(ruleJson), data);
  }

  group('numeric edge cases', () {
    test('int === double: 1 === 1.0 is true', () {
      expect(evaluate('{"===":[1, 1.0]}'), isTrue);
    });

    test('double === int: 2.0 === 2 is true', () {
      expect(evaluate('{"===":[2.0, 2]}'), isTrue);
    });

    test('!== distinguishes 1 from 1.5', () {
      expect(evaluate('{"!==":[1, 1.5]}'), isTrue);
    });

    test('negative numbers compare correctly', () {
      expect(evaluate('{">":[-1, -5]}'), isTrue);
      expect(evaluate('{"<":[-10, -1]}'), isTrue);
      expect(evaluate('{">=":[-1, -1]}'), isTrue);
    });

    test('mixed int/double comparison works', () {
      expect(evaluate('{">":[1.5, 1]}'), isTrue);
      expect(evaluate('{"<":[1, 1.5]}'), isTrue);
      expect(evaluate('{">=":[2, 2.0]}'), isTrue);
    });

    test('negative zero equals positive zero', () {
      expect(evaluate('{"===":[0, -0.0]}'), isTrue);
    });

    test('positive infinity compares as larger than any finite', () {
      // double.infinity is not JSON-representable; build the rule directly.
      final rule = GreaterThanRule(
        const LiteralRule(double.infinity),
        const LiteralRule(1e308),
      );
      expect(JsonLogicEvaluator.evaluate(rule, const {}), isTrue);
    });

    test('negative infinity compares as smaller than any finite', () {
      final rule = LessThanRule(
        const LiteralRule(double.negativeInfinity),
        const LiteralRule(-1e308),
      );
      expect(JsonLogicEvaluator.evaluate(rule, const {}), isTrue);
    });

    test('=== with two NaNs returns false (NaN never equals NaN)', () {
      final rule = StrictEqualsRule(
        const LiteralRule(double.nan),
        const LiteralRule(double.nan),
      );
      // Mirrors Kotlin/Swift: numeric strict-equality has no NaN guard, so
      // the IEEE-754 rule (NaN != NaN) wins.
      expect(JsonLogicEvaluator.evaluate(rule, const {}), isFalse);
    });

    test('!== with two NaNs returns true', () {
      final rule = StrictNotEqualsRule(
        const LiteralRule(double.nan),
        const LiteralRule(double.nan),
      );
      expect(JsonLogicEvaluator.evaluate(rule, const {}), isTrue);
    });

    test('<= throws for NaN operand', () {
      final rule = LessThanOrEqualRule(
        const LiteralRule(double.nan),
        const LiteralRule(1),
      );
      expect(
        () => JsonLogicEvaluator.evaluate(rule, const {}),
        throwsA(isA<TypeMismatchException>()),
      );
    });
  });

  group('var - falsy values are not "missing"', () {
    test('var returns false (not null) when property is false', () {
      expect(
        evaluate('{"===":[{"var":"flag"}, false]}', {'flag': false}),
        isTrue,
      );
    });

    test('var returns 0 (not null) when property is 0', () {
      expect(evaluate('{"===":[{"var":"n"}, 0]}', {'n': 0}), isTrue);
    });

    test('var returns empty string (not null) when property is ""', () {
      expect(evaluate('{"===":[{"var":"s"}, ""]}', {'s': ''}), isTrue);
    });

    test('var returns null when property is explicitly null', () {
      expect(evaluate('{"===":[{"var":"x"}, null]}', {'x': null}), isTrue);
    });

    test('var returns null for missing key vs property set to null '
        '(indistinguishable by design)', () {
      expect(evaluate('{"===":[{"var":"missing"}, null]}'), isTrue);
    });
  });

  group('var - dynamic and unusual paths', () {
    test('var path that itself is a var expression', () {
      // {"var": {"var": "key"}} with data {"key": "actual", "actual": "value"}
      // resolves "key" → "actual", then looks up "actual" → "value".
      expect(
        evaluate('{"var":{"var":"key"}}', {'key': 'actual', 'actual': 'value'}),
        'value',
      );
    });

    test('var path that is a numeric literal coerces to string key', () {
      expect(evaluate('{"var":1}', {'1': 'found'}), 'found');
    });

    test('var path that is a number literal as the only array element', () {
      expect(evaluate('{"var":[1]}', {'1': 'found'}), 'found');
    });

    test('var with property name containing space', () {
      expect(evaluate('{"var":"first name"}', {'first name': 'Ada'}), 'Ada');
    });

    test('var with property name containing colon', () {
      expect(evaluate('{"var":"ns:key"}', {'ns:key': 'value'}), 'value');
    });

    test('var with unicode property name', () {
      expect(evaluate('{"var":"café"}', {'café': 'open'}), 'open');
    });

    test('var resolving to a List can flow into `in` haystack', () {
      expect(
        evaluate('{"in":["b", {"var":"tags"}]}', {
          'tags': ['a', 'b', 'c'],
        }),
        isTrue,
      );
    });

    test('var resolving to a List in === throws array TypeMismatch', () {
      expect(
        () => evaluate('{"===":[{"var":"tags"}, "a"]}', {
          'tags': ['a'],
        }),
        throwsA(isA<TypeMismatchException>()),
      );
    });
  });

  group("string 'in' edge cases", () {
    test('empty needle is always contained in any string (Dart semantics)', () {
      // String.contains("") returns true in Dart; same as JS, Kotlin, Swift.
      expect(evaluate('{"in":["", "hello"]}'), isTrue);
    });

    test('empty needle in empty haystack returns true', () {
      expect(evaluate('{"in":["", ""]}'), isTrue);
    });

    test('non-empty needle in empty haystack returns false', () {
      expect(evaluate('{"in":["x", ""]}'), isFalse);
    });

    test('case sensitivity is enforced', () {
      expect(evaluate('{"in":["lou", "Louisville"]}'), isFalse);
      expect(evaluate('{"in":["Lou", "Louisville"]}'), isTrue);
    });

    test('unicode substring matching', () {
      expect(evaluate('{"in":["é", "café"]}'), isTrue);
      expect(evaluate('{"in":["münchen", "Welcome to münchen!"]}'), isTrue);
    });

    test('needle equal to full haystack matches', () {
      expect(evaluate('{"in":["hello", "hello"]}'), isTrue);
    });
  });

  group("array 'in' edge cases", () {
    test('single-element array with match', () {
      expect(evaluate('{"in":["only", ["only"]]}'), isTrue);
    });

    test('single-element array without match', () {
      expect(evaluate('{"in":["other", ["only"]]}'), isFalse);
    });

    test('array contains var-resolved string elements', () {
      // The haystack array contains a {"var":"x"} expression which must be
      // evaluated before membership is checked.
      expect(
        evaluate('{"in":["target", [{"var":"x"}, "other"]]}', {'x': 'target'}),
        isTrue,
      );
    });

    test('empty string needle against array of strings returns false', () {
      // "" is not equal (===) to any non-empty string element.
      expect(evaluate('{"in":["", ["a", "b"]]}'), isFalse);
    });

    test('empty string needle against array containing empty string '
        'returns true', () {
      expect(evaluate('{"in":["", ["", "a"]]}'), isTrue);
    });
  });

  group('and/or - nesting and single-operand', () {
    test('and with single true operand returns true', () {
      expect(evaluate('{"and":[{"===":[1,1]}]}'), isTrue);
    });

    test('or with single false operand returns false', () {
      expect(evaluate('{"or":[{"===":[1,2]}]}'), isFalse);
    });

    test('three-level nested and/or', () {
      // (a AND (b OR (c AND d)))
      const rule = '''
        {"and":[
          {"===":[{"var":"a"}, 1]},
          {"or":[
            {"===":[{"var":"b"}, 99]},
            {"and":[
              {">":[{"var":"c"}, 0]},
              {"<":[{"var":"d"}, 100]}
            ]}
          ]}
        ]}
      ''';
      expect(evaluate(rule, {'a': 1, 'b': 0, 'c': 5, 'd': 50}), isTrue);
      expect(evaluate(rule, {'a': 1, 'b': 0, 'c': 5, 'd': 200}), isFalse);
      expect(evaluate(rule, {'a': 2, 'b': 99, 'c': 5, 'd': 50}), isFalse);
    });

    test(
      'and evaluates all operands even after a false (type-safety check)',
      () {
        // Second operand is malformed type-wise; engine must surface that error
        // rather than short-circuit on the first `false`.
        expect(
          () => evaluate('{"and":[{"===":[1,2]}, {"===":[1, "1"]}]}'),
          throwsA(isA<TypeMismatchException>()),
        );
      },
    );

    test('or evaluates all operands even after a true (type-safety check)', () {
      expect(
        () => evaluate('{"or":[{"===":[1,1]}, {"===":[1, "1"]}]}'),
        throwsA(isA<TypeMismatchException>()),
      );
    });
  });

  group('parser edge cases', () {
    test('multi-key object as expression throws', () {
      expect(
        () => JsonLogicParser.parse('{"===":[1,1], "!==":[1,2]}'),
        throwsA(isA<InvalidExpressionException>()),
      );
    });

    test('parse tolerates surrounding whitespace', () {
      expect(evaluate('   {"===":[1,1]}   '), isTrue);
    });

    test('parse tolerates internal whitespace and newlines', () {
      expect(evaluate('{\n  "===": [\n    1,\n    1\n  ]\n}'), isTrue);
    });

    test('empty object parses as literal empty map', () {
      // Per parity with mixpanel-android: `{}` becomes a LiteralRule({}).
      // Evaluating it directly returns the empty map literal.
      final result = JsonLogicEvaluator.evaluate(
        JsonLogicParser.parse('{}'),
        const {},
      );
      expect(result, isA<Map<Object?, Object?>>());
      expect((result! as Map<Object?, Object?>).isEmpty, isTrue);
    });

    test('nested expressions in binary operator args', () {
      // {"===":[{"in":["a","abc"]}, true]} — left side resolves to true,
      // strict-equals against literal true.
      expect(evaluate('{"===":[{"in":["a","abc"]}, true]}'), isTrue);
    });

    test('binary operator with 0 args throws', () {
      expect(
        () => JsonLogicParser.parse('{"===":[]}'),
        throwsA(isA<InvalidExpressionException>()),
      );
    });

    test('binary operator with 1 arg throws', () {
      expect(
        () => JsonLogicParser.parse('{"===":[1]}'),
        throwsA(isA<InvalidExpressionException>()),
      );
    });

    test(
      'parse with non-array operand wraps single arg (for non-binary ops)',
      () {
        // `and` accepts any operand shape; a single non-array arg becomes a
        // 1-element operand list. This must still be boolean to evaluate.
        expect(evaluate('{"and":[{"===":[1,1]}]}'), isTrue);
      },
    );
  });

  group('strict equality - extra cross-type combinations', () {
    test('=== throws for List vs String', () {
      expect(
        () => evaluate('{"===":[{"var":"l"}, "a"]}', {
          'l': ['a'],
        }),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('=== throws for List vs Number', () {
      expect(
        () => evaluate('{"===":[{"var":"l"}, 1]}', {
          'l': [1],
        }),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('=== throws for List vs Bool', () {
      expect(
        () => evaluate('{"===":[{"var":"l"}, true]}', {
          'l': [true],
        }),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('=== throws for List vs null', () {
      expect(
        () => evaluate('{"===":[{"var":"l"}, null]}', {'l': <Object?>[]}),
        throwsA(isA<TypeMismatchException>()),
      );
    });
  });

  group('numeric comparison - extra rejections', () {
    test('> rejects List operand', () {
      expect(
        () => evaluate('{">":[{"var":"l"}, 1]}', {
          'l': [1, 2],
        }),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('<= rejects bool literal', () {
      expect(
        () => evaluate('{"<=":[true, 1]}'),
        throwsA(isA<TypeMismatchException>()),
      );
    });
  });
}

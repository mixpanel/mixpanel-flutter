import 'package:test/test.dart';
import 'package:mixpanel_flutter_common/mixpanel_flutter_common.dart';

/// Mirrors `JsonLogicEdgeCaseTest.kt` from mixpanel-android. Covers scenarios
/// not exercised by the shared `tests.json` fixture — primarily error paths
/// and the unsupported-operator allowlist.
void main() {
  Object? evaluate(String ruleJson, [Map<String, Object?> data = const {}]) {
    return JsonLogicEvaluator.evaluate(JsonLogicParser.parse(ruleJson), data);
  }

  group('var', () {
    test('throws for dot in property name', () {
      expect(
        () => evaluate('{"var":"user.name"}', {
          'user': {'name': 'John'},
        }),
        throwsA(isA<InvalidExpressionException>()),
      );
    });

    test('throws for multiple dots in property name', () {
      expect(
        () => evaluate('{"var":"a.b.c"}', {
          'a': {
            'b': {'c': 42},
          },
        }),
        throwsA(isA<InvalidExpressionException>()),
      );
    });

    test('accesses property with numeric string key', () {
      expect(evaluate('{"var":"0"}', {'0': 'first', '1': 'second'}), 'first');
    });

    test('accesses property with dollar sign in name', () {
      expect(evaluate('{"var":"\$tier"}', {'\$tier': 'premium'}), 'premium');
    });

    test('throws for default value syntax (parse time)', () {
      expect(
        () => JsonLogicParser.parse('{"var": ["missing", 0]}'),
        throwsA(isA<InvalidExpressionException>()),
      );
    });

    test('throws for empty path', () {
      expect(
        () => evaluate('{"var":""}', {'a': 1}),
        throwsA(isA<InvalidExpressionException>()),
      );
    });

    test('throws for null path', () {
      expect(
        () => evaluate('{"var":null}', {'a': 1}),
        throwsA(isA<InvalidExpressionException>()),
      );
    });

    test('throws for empty array path', () {
      expect(
        () => evaluate('{"var":[]}', {'a': 1}),
        throwsA(isA<InvalidExpressionException>()),
      );
    });
  });

  group("'in' operator", () {
    test('matches string in array', () {
      expect(
        evaluate('{"in": [{"var": "tier"}, ["a", "b", "c"]]}', {'tier': 'b'}),
        isTrue,
      );
    });

    test('returns false when string not in array', () {
      expect(
        evaluate('{"in": [{"var": "tier"}, ["a", "b", "c"]]}', {'tier': 'x'}),
        isFalse,
      );
    });

    test('throws when array contains non-string elements', () {
      expect(
        () => evaluate('{"in": [{"var": "tier"}, [1, 2, 3]]}', {'tier': '1'}),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('throws when array contains mixed types', () {
      expect(
        () =>
            evaluate('{"in": [{"var": "tier"}, ["a", 1, "b"]]}', {'tier': 'x'}),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('throws when array contains null', () {
      expect(
        () => evaluate('{"in": [{"var": "tier"}, ["a", null]]}', {'tier': 'a'}),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('returns false for empty array', () {
      expect(evaluate('{"in": [{"var": "tier"}, []]}', {'tier': 'a'}), isFalse);
    });

    test('matches substring in string', () {
      expect(
        evaluate('{"in": ["Lou", {"var": "city"}]}', {'city': 'Louisville'}),
        isTrue,
      );
    });

    test('returns false when substring not in string', () {
      expect(
        evaluate('{"in": ["xyz", {"var": "city"}]}', {'city': 'Louisville'}),
        isFalse,
      );
    });

    test('throws for number needle', () {
      expect(
        () => evaluate('{"in": [{"var": "id"}, ["1", "2", "3"]]}', {'id': 2}),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('throws for boolean needle', () {
      expect(
        () => evaluate('{"in": [{"var": "active"}, ["true", "false"]]}', {
          'active': true,
        }),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('throws for null needle', () {
      expect(
        () =>
            evaluate('{"in": [{"var": "value"}, ["a", "b"]]}', {'value': null}),
        throwsA(isA<TypeMismatchException>()),
      );
    });
  });

  group('strict equality', () {
    test('=== returns true for matching nulls', () {
      expect(
        evaluate('{"===": [{"var": "value"}, null]}', {'value': null}),
        isTrue,
      );
    });

    test('=== returns true for matching numbers', () {
      expect(
        evaluate('{"===": [{"var": "count"}, 42]}', {'count': 42}),
        isTrue,
      );
    });

    // Int-precision fast path: two distinct 64-bit ints above 2^53 must
    // not be considered equal. mixpanel-android's evaluator collapses to
    // double here and loses precision — Flutter follows mixpanel-swift-
    // common which preserves int precision.
    test('=== returns false for distinct ints above 2^53', () {
      // 2^53 + 1 vs 2^53 + 2 — both round to the same double (2^53 + 2).
      expect(
        evaluate('{"===": [{"var": "a"}, {"var": "b"}]}', {
          'a': 9007199254740993,
          'b': 9007199254740994,
        }),
        isFalse,
      );
    });

    test('=== returns true for matching ints above 2^53', () {
      expect(
        evaluate('{"===": [{"var": "a"}, {"var": "b"}]}', {
          'a': 9007199254740993,
          'b': 9007199254740993,
        }),
        isTrue,
      );
    });

    test('=== returns true for mixed int and double of equal value', () {
      // The mixed-type case still goes through Double coercion so
      // `1 === 1.0` keeps returning true (JS-style numeric semantics).
      expect(
        evaluate('{"===": [{"var": "a"}, {"var": "b"}]}', {
          'a': 1,
          'b': 1.0,
        }),
        isTrue,
      );
    });

    test('=== returns true for matching doubles', () {
      expect(
        evaluate('{"===": [{"var": "a"}, {"var": "b"}]}', {
          'a': 1.5,
          'b': 1.5,
        }),
        isTrue,
      );
    });

    test('!== returns false for matching numbers', () {
      expect(evaluate('{"!==": [{"var": "count"}, 1]}', {'count': 1}), isFalse);
    });

    test('!== returns true for different strings', () {
      expect(
        evaluate('{"!==": [{"var": "greeting"}, "world"]}', {
          'greeting': 'hello',
        }),
        isTrue,
      );
    });

    test('=== throws for number vs string', () {
      expect(
        () => evaluate('{"===": [{"var": "count"}, "1"]}', {'count': 1}),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('=== throws for boolean vs string', () {
      expect(
        () =>
            evaluate('{"===": [{"var": "active"}, "true"]}', {'active': true}),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('=== throws for boolean vs number', () {
      expect(
        () => evaluate('{"===": [{"var": "active"}, 1]}', {'active': true}),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('=== throws for null vs number', () {
      expect(
        () => evaluate('{"===": [{"var": "value"}, 0]}', {'value': null}),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('=== throws for null vs string', () {
      expect(
        () => evaluate('{"===": [{"var": "value"}, ""]}', {'value': null}),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('!== throws for number vs string', () {
      expect(
        () => evaluate('{"!==": [{"var": "count"}, "1"]}', {'count': 1}),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('!== throws for null vs number', () {
      expect(
        () => evaluate('{"!==": [{"var": "value"}, 0]}', {'value': null}),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('!== throws for boolean vs string', () {
      expect(
        () =>
            evaluate('{"!==": [{"var": "active"}, "true"]}', {'active': true}),
        throwsA(isA<TypeMismatchException>()),
      );
    });
  });

  group('array comparison', () {
    test('=== throws for array comparison', () {
      expect(
        () => evaluate('{"===": [{"var": "list"}, [1]]}', {
          'list': [1],
        }),
        throwsA(isA<TypeMismatchException>()),
      );
    });
  });

  group('compound rules', () {
    test('and - complex rule with nested operations', () {
      expect(
        evaluate(
          '{"and": [{">=": [{"var": "age"}, 18]}, {"var": "premium"}]}',
          {'age': 25, 'premium': true},
        ),
        isTrue,
      );
    });

    test('and - returns true when all operands true', () {
      expect(
        evaluate(
          '{"and": [{"===": [{"var": "a"}, 1]}, {"===": [{"var": "b"}, 2]}]}',
          {'a': 1, 'b': 2},
        ),
        isTrue,
      );
    });

    test('and - returns false when any operand false', () {
      expect(
        evaluate(
          '{"and": [{"===": [{"var": "a"}, 1]}, {"===": [{"var": "b"}, 3]}]}',
          {'a': 1, 'b': 2},
        ),
        isFalse,
      );
    });

    test('or - returns true when any operand true', () {
      expect(
        evaluate(
          '{"or": [{"===": [{"var": "a"}, 9]}, {"===": [{"var": "b"}, 2]}]}',
          {'a': 1, 'b': 2},
        ),
        isTrue,
      );
    });

    test('or - returns false when all operands false', () {
      expect(
        evaluate(
          '{"or": [{"===": [{"var": "a"}, 9]}, {"===": [{"var": "b"}, 9]}]}',
          {'a': 1, 'b': 2},
        ),
        isFalse,
      );
    });

    test('and - throws for number literal operand', () {
      expect(
        () => evaluate('{"and": [{"var": "active"}, 1]}', {'active': true}),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('or - throws for string literal operand', () {
      expect(
        () =>
            evaluate('{"or": [{"var": "active"}, "hello"]}', {'active': false}),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('and - throws for var returning non-boolean', () {
      expect(
        () => evaluate('{"and": [{"var": "active"}, {"var": "count"}]}', {
          'active': true,
          'count': 5,
        }),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('or - throws for null operand', () {
      expect(
        () => evaluate('{"or": [{"var": "active"}, null]}', {'active': false}),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('and - throws for empty operands', () {
      expect(
        () => evaluate('{"and": []}'),
        throwsA(isA<InvalidExpressionException>()),
      );
    });

    test('or - throws for empty operands', () {
      expect(
        () => evaluate('{"or": []}'),
        throwsA(isA<InvalidExpressionException>()),
      );
    });

    test('< throws for 3 args (parse time)', () {
      expect(
        () => JsonLogicParser.parse('{"<": [1, 5, 10]}'),
        throwsA(isA<InvalidExpressionException>()),
      );
    });

    test('<= throws for 3 args (parse time)', () {
      expect(
        () => JsonLogicParser.parse('{"<=": [1, 1, 10]}'),
        throwsA(isA<InvalidExpressionException>()),
      );
    });
  });

  group('numeric comparison rejects non-numbers', () {
    test('> throws for string operand', () {
      expect(
        () => evaluate('{">": [{"var": "age"}, 5]}', {'age': '10'}),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('< throws for string operand', () {
      expect(
        () => evaluate('{"<": [{"var": "age"}, "10"]}', {'age': 5}),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('>= throws for string operands', () {
      expect(
        () => evaluate('{">=": [{"var": "name"}, "def"]}', {'name': 'abc'}),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('<= throws for string operands', () {
      expect(
        () => evaluate('{"<=": [{"var": "value"}, "2"]}', {'value': '1'}),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('> throws for null operand', () {
      expect(
        () => evaluate('{">": [{"var": "value"}, 5]}', {'value': null}),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('< throws for null operand', () {
      expect(
        () => evaluate('{"<": [{"var": "age"}, {"var": "limit"}]}', {
          'age': 5,
          'limit': null,
        }),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('> throws for NaN', () {
      // NaN cannot be expressed in JSON, so build the rule tree directly.
      final rule = GreaterThanRule(LiteralRule(double.nan), LiteralRule(1));
      expect(
        () => JsonLogicEvaluator.evaluate(rule, const {}),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('> throws for boolean operand', () {
      expect(
        () => evaluate('{">": [true, false]}'),
        throwsA(isA<TypeMismatchException>()),
      );
    });
  });

  group('unsupported operators (parse-time guardrails)', () {
    // Per product decision, only 10 operators are supported. These tests
    // prevent accidental reintroduction.
    final unsupported = <String, String>{
      '== (loose equals)': '{"==":[1, "1"]}',
      '!= (loose not equals)': '{"!=":[1, 2]}',
      '! (not)': '{"!":[true]}',
      '!! (double bang)': '{"!!":[1]}',
      'if': '{"if":[true, 1, 2]}',
      '?: (ternary)': '{"?:":[true, 1, 2]}',
      '+ (addition)': '{"+":[1, 2]}',
      '- (subtraction)': '{"-":[3, 1]}',
      '* (multiplication)': '{"*":[2, 3]}',
      '/ (division)': '{"/":[6, 2]}',
      '% (modulo)': '{"%":[5, 2]}',
      'min': '{"min":[1, 2, 3]}',
      'max': '{"max":[1, 2, 3]}',
      'cat': '{"cat":["a", "b"]}',
      'substr': '{"substr":["hello", 0, 2]}',
      'map': '{"map":[[1,2,3], {"var":""}]}',
      'filter': '{"filter":[[1,2,3], {"var":""}]}',
      'reduce': '{"reduce":[[1,2,3], {"var":"current"}, 0]}',
      'all': '{"all":[[1,2,3], {"var":""}]}',
      'some': '{"some":[[1,2,3], {"var":""}]}',
      'none': '{"none":[[1,2,3], {"var":""}]}',
      'merge': '{"merge":[[1,2], [3,4]]}',
      'missing': '{"missing":["a", "b"]}',
      'missing_some': '{"missing_some":[1, ["a", "b"]]}',
      'log': '{"log":"test"}',
    };

    for (final entry in unsupported.entries) {
      test('${entry.key} throws UnsupportedOperatorException', () {
        expect(
          () => JsonLogicParser.parse(entry.value),
          throwsA(isA<UnsupportedOperatorException>()),
        );
      });
    }
  });

  group('parse - only JSON objects accepted', () {
    test('throws for boolean literal', () {
      expect(
        () => JsonLogicParser.parse('true'),
        throwsA(isA<InvalidExpressionException>()),
      );
    });

    test('throws for number literal', () {
      expect(
        () => JsonLogicParser.parse('42'),
        throwsA(isA<InvalidExpressionException>()),
      );
    });

    test('throws for string literal', () {
      expect(
        () => JsonLogicParser.parse('"hello"'),
        throwsA(isA<InvalidExpressionException>()),
      );
    });

    test('throws for null literal', () {
      expect(
        () => JsonLogicParser.parse('null'),
        throwsA(isA<InvalidExpressionException>()),
      );
    });

    test('throws for array', () {
      expect(
        () => JsonLogicParser.parse('["a", "b"]'),
        throwsA(isA<InvalidExpressionException>()),
      );
    });

    test('throws for malformed JSON', () {
      expect(
        () => JsonLogicParser.parse('{"===" 1, 1]}'),
        throwsA(isA<InvalidExpressionException>()),
      );
    });
  });
}

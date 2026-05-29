import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:mixpanel_flutter_common/mixpanel_flutter_common.dart';

/// Mirrors `JsonLogicTest.kt` from mixpanel-android: a parameterized fixture
/// runner backed by `tests.json` to keep parity across SDK ports.
void main() {
  final fixturePath = 'test/jsonlogic/tests.json';
  final raw = File(fixturePath).readAsStringSync();
  final entries = jsonDecode(raw) as List<Object?>;

  var currentSection = 'tests';
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    if (entry is String) {
      final trimmed = entry.replaceFirst(RegExp(r'^#\s*'), '').trim();
      if (trimmed.isNotEmpty && !trimmed.split('').every((c) => c == '=')) {
        currentSection = trimmed;
      }
      continue;
    }
    if (entry is! List || entry.length < 3) {
      throw StateError(
        'Malformed fixture entry at index $i in $fixturePath: '
        'expected a [rule, data, expected] triple, got ${jsonEncode(entry)}',
      );
    }

    final rule = entry[0];
    final data = entry[1];
    final expected = entry[2];

    final name =
        'group: $currentSection, rule: ${jsonEncode(rule)}, '
        'result: ${jsonEncode(expected)}';

    test(name, () {
      // Data must be a JSON object per the supported subset (var operates on
      // dict context only); throw early in the test if the fixture provides
      // anything else.
      if (data is! Map) {
        fail('Test data must be a JSON object, got: ${jsonEncode(data)}');
      }
      final parsedRule = JsonLogicParser.parse(jsonEncode(rule));
      final result = JsonLogicEvaluator.evaluate(
        parsedRule,
        data.cast<String, Object?>(),
      );
      expect(
        _valuesEqual(result, expected),
        isTrue,
        reason:
            'Expected: $expected (${expected?.runtimeType}), '
            'Got: $result (${result?.runtimeType})',
      );
    });
  }
}

bool _valuesEqual(Object? actual, Object? expected) {
  if (actual == null && expected == null) return true;
  if (actual == null || expected == null) return false;

  if (actual is num && expected is num) {
    return (actual.toDouble() - expected.toDouble()).abs() < 0.0001;
  }

  if (actual is bool && expected is bool) return actual == expected;
  if (actual is String && expected is String) return actual == expected;

  if (actual is List && expected is List) {
    if (actual.length != expected.length) return false;
    for (var i = 0; i < actual.length; i++) {
      if (!_valuesEqual(actual[i], expected[i])) return false;
    }
    return true;
  }

  if (actual is Map && expected is Map) {
    if (actual.length != expected.length) return false;
    for (final key in actual.keys) {
      if (!expected.containsKey(key)) return false;
      if (!_valuesEqual(actual[key], expected[key])) return false;
    }
    return true;
  }

  return actual == expected;
}

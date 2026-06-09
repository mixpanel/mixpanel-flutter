import 'dart:convert';

import 'json_logic_exception.dart';
import 'json_logic_rule.dart';

/// Parser that converts raw JSON into a typed [JsonLogicRule] tree.
///
/// Supported operators (per Event Trigger alignment decision):
/// - Comparison: ===, !==, <, <=, >, >=
/// - Logic: and, or
/// - String/Array: in
/// - Data Access: var
///
/// Example:
/// ```dart
/// final rule = JsonLogicParser.parse('{"===":[1,1]}');
/// ```
class JsonLogicParser {
  const JsonLogicParser._();

  /// Maximum nesting depth allowed in a rule tree.
  ///
  /// Bounded to prevent a malicious server-supplied rule from causing a
  /// stack overflow in either the parser or the evaluator (which recurses
  /// through the parsed tree). 100 is well above any realistic rule —
  /// real-world Event Trigger rules are typically 3–5 levels deep.
  static const int maxDepth = 100;

  /// Maximum length of attacker-controlled input echoed back in error
  /// messages. Prevents megabyte-sized rules from producing megabyte-sized
  /// log lines.
  static const int _maxErrorEchoLength = 200;

  /// Parses a JSON string into a typed [JsonLogicRule].
  ///
  /// Throws [JsonLogicException] if the JSON is malformed, contains
  /// unsupported operations, or exceeds [maxDepth].
  static JsonLogicRule parse(String json) {
    final trimmed = json.trim();
    if (!trimmed.startsWith('{')) {
      throw InvalidExpressionException(
        'parse',
        "input must be a JSON object: '${_truncate(trimmed)}'",
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      throw InvalidExpressionException(
        'parse',
        "malformed JSON object: '${_truncate(trimmed)}'",
      );
    }
    if (decoded is! Map) {
      throw InvalidExpressionException(
        'parse',
        "input must be a JSON object: '${_truncate(trimmed)}'",
      );
    }
    return _parseValue(decoded);
  }

  /// Recursive helper for [parse]. Walks a decoded JSON value and produces
  /// the corresponding [JsonLogicRule] subtree, enforcing [maxDepth].
  static JsonLogicRule _parseValue(Object? value, [int depth = 0]) {
    if (depth > maxDepth) {
      throw InvalidExpressionException(
        'parse',
        'rule nesting depth exceeds maximum of $maxDepth',
      );
    }
    if (value == null) return const LiteralRule(null);
    if (value is bool) return LiteralRule(value);
    if (value is num) return LiteralRule(value);
    if (value is String) return LiteralRule(value);
    if (value is List) return _parseArray(value, depth);
    if (value is Map) return _parseObject(value, depth);
    throw TypeMismatchException(
      'value',
      'unsupported type: ${value.runtimeType}',
    );
  }

  static JsonLogicRule _parseArray(List<Object?> array, int depth) {
    final elements = array
        .map((e) => _parseValue(e, depth + 1))
        .toList(growable: false);
    final hasRules = elements.any((e) => e is! LiteralRule);
    if (hasRules) {
      return ArrayRule(elements);
    }
    return LiteralRule(
      elements.map((e) => (e as LiteralRule).value).toList(growable: false),
    );
  }

  static JsonLogicRule _parseObject(Map<Object?, Object?> obj, int depth) {
    if (obj.isEmpty) {
      return const LiteralRule(<String, Object?>{});
    }
    if (obj.length != 1) {
      throw InvalidExpressionException(
        'rule',
        'must have exactly one operator, found: '
            '${_truncate(obj.keys.toList().toString())}',
      );
    }

    final operator = obj.keys.first.toString();
    final args = obj.values.first;

    return _parseOperator(operator, args, depth);
  }

  static JsonLogicRule _parseOperator(
    String operator,
    Object? args,
    int depth,
  ) {
    final operands = _toOperandList(args, depth);

    switch (operator) {
      // Comparison
      case '===':
        return _requireBinary(operator, operands, (l, r) => StrictEqualsRule(l, r));
      case '!==':
        return _requireBinary(operator, operands, (l, r) => StrictNotEqualsRule(l, r));
      case '>':
        return _requireBinary(operator, operands, (l, r) => GreaterThanRule(l, r));
      case '>=':
        return _requireBinary(operator, operands, (l, r) => GreaterThanOrEqualRule(l, r));
      case '<':
        return _requireBinary(operator, operands, (l, r) => LessThanRule(l, r));
      case '<=':
        return _requireBinary(operator, operands, (l, r) => LessThanOrEqualRule(l, r));

      // Logic
      case 'and':
        return AndRule(operands);
      case 'or':
        return OrRule(operands);

      // String/Array
      case 'in':
        return _requireBinary(operator, operands, (l, r) => InRule(l, r));

      // Data access
      case 'var':
        return _parseVarRule(operands);

      default:
        throw UnsupportedOperatorException(operator);
    }
  }

  static VarRule _parseVarRule(List<JsonLogicRule> operands) {
    if (operands.isEmpty) {
      return const VarRule(LiteralRule(''));
    }
    if (operands.length == 1) {
      return VarRule(operands[0]);
    }
    throw InvalidExpressionException('var', 'default values are not supported');
  }

  static List<JsonLogicRule> _toOperandList(Object? args, int depth) {
    if (args == null) {
      return const [LiteralRule(null)];
    }
    if (args is List) {
      return args.map((e) => _parseValue(e, depth + 1)).toList(growable: false);
    }
    return [_parseValue(args, depth + 1)];
  }

  static T _requireBinary<T extends JsonLogicRule>(
    String operator,
    List<JsonLogicRule> operands,
    T Function(JsonLogicRule, JsonLogicRule) factory,
  ) {
    if (operands.length != 2) {
      throw InvalidExpressionException(
        operator,
        'requires exactly 2 arguments, got ${operands.length}',
      );
    }
    return factory(operands[0], operands[1]);
  }

  static String _truncate(String input) {
    if (input.length <= _maxErrorEchoLength) return input;
    return '${input.substring(0, _maxErrorEchoLength)}...';
  }
}

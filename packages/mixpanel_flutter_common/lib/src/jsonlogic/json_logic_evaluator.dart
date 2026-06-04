import 'json_logic_exception.dart';
import 'json_logic_rule.dart';

/// Evaluates typed [JsonLogicRule] trees against JSON data.
///
/// The evaluator walks the typed rule tree without string-matching on
/// operator names.
///
/// Supported operators: `===`, `!==`, `<`, `<=`, `>`, `>=`, `and`, `or`, `in`,
/// `var`
///
/// ## Operator Assumptions
///
/// ### Strict Equality (`===`, `!==`)
/// - `null` can only equal `null`; comparing `null` with non-null throws
///   [TypeMismatchException]
/// - Array comparison is not supported; throws [TypeMismatchException]
/// - Numbers are compared by value regardless of int/double subtype
///   (`1 === 1.0` is `true`)
/// - Non-null, non-number operands must be the same type; otherwise throws
///   [TypeMismatchException]
///
/// ### Numeric Comparison (`>`, `<`, `>=`, `<=`)
/// - Both operands must be numbers; non-numeric operands throw
///   [TypeMismatchException]
/// - `NaN` values are not supported; throws [TypeMismatchException]
///
/// ### Logic (`and`, `or`)
/// - Requires at least 1 operand; empty operands throw
///   [InvalidExpressionException]
/// - All operands must evaluate to `bool`; non-boolean results throw
///   [TypeMismatchException]
/// - All operands are evaluated (no short-circuit) to ensure type safety
///
/// ### Membership/Substring (`in`)
/// - Needle must be a `String`; non-string needles throw
///   [TypeMismatchException]
/// - Haystack must be a `String` or array; other types throw
///   [TypeMismatchException]
/// - For string haystack: performs substring check
/// - For array haystack: checks membership using strict equality (all elements
///   validated)
///
/// ### Data Access (`var`)
/// - Property name is required; empty path throws [InvalidExpressionException]
/// - Dots in property names are not allowed; throws
///   [InvalidExpressionException]
/// - Returns `null` if the property does not exist
class JsonLogicEvaluator {
  const JsonLogicEvaluator._();

  /// Evaluates a JsonLogic rule against event properties.
  ///
  /// The return type is [Object?] because JsonLogic is dynamically typed and
  /// different operations return different types.
  static Object? evaluate(JsonLogicRule rule, Map<String, Object?> data) {
    if (rule is LiteralRule) return rule.value;
    if (rule is ArrayRule) {
      return rule.elements.map((e) => evaluate(e, data)).toList();
    }
    // Comparison
    if (rule is StrictEqualsRule) {
      return _strictEquals(evaluate(rule.left, data), evaluate(rule.right, data));
    }
    if (rule is StrictNotEqualsRule) {
      return !_strictEquals(evaluate(rule.left, data), evaluate(rule.right, data));
    }
    if (rule is GreaterThanRule) {
      return _compareValues(evaluate(rule.left, data), evaluate(rule.right, data)) > 0;
    }
    if (rule is GreaterThanOrEqualRule) {
      return _compareValues(evaluate(rule.left, data), evaluate(rule.right, data)) >= 0;
    }
    if (rule is LessThanRule) {
      return _compareValues(evaluate(rule.left, data), evaluate(rule.right, data)) < 0;
    }
    if (rule is LessThanOrEqualRule) {
      return _compareValues(evaluate(rule.left, data), evaluate(rule.right, data)) <= 0;
    }
    // Logic
    if (rule is AndRule) return _evaluateAnd(rule.operands, data);
    if (rule is OrRule) return _evaluateOr(rule.operands, data);
    // String/Array
    if (rule is InRule) return _evaluateIn(rule, data);
    // Data access
    if (rule is VarRule) return _evaluateVar(rule, data);
    throw StateError('Unhandled JsonLogicRule subtype: ${rule.runtimeType}');
  }

  // ===========================================================================
  // Comparison helpers
  // ===========================================================================

  /// Strict equality (===) - operands must be the same type.
  ///
  /// Throws [TypeMismatchException] if types don't match.
  static bool _strictEquals(Object? a, Object? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) {
      throw TypeMismatchException('===', 'operands must be the same type');
    }

    if (a is List || b is List) {
      throw TypeMismatchException('===', 'does not support array comparison');
    }

    // bool must be checked before num: Dart does not bridge bool↔num, but we
    // still gate on type before falling through to numeric comparison.
    if (a is bool || b is bool) {
      if (a is! bool || b is! bool) {
        throw TypeMismatchException('===', 'operands must be the same type');
      }
      return a == b;
    }

    if (a is num && b is num) {
      // Compare ints directly so 64-bit values above 2^53 don't collapse
      // to the same double mantissa (transaction/session IDs, ns
      // timestamps). Matches mixpanel-swift-common's JSONLogicEvaluator,
      // which also tries Int === Int before falling back to Double
      // coercion for mixed int+double cases. (mixpanel-android currently
      // coerces everything to double and loses this precision — Flutter
      // intentionally diverges to match the more accurate iOS behavior.)
      if (a is int && b is int) return a == b;
      return a.toDouble() == b.toDouble();
    }

    if (a.runtimeType != b.runtimeType) {
      throw TypeMismatchException('===', 'operands must be the same type');
    }
    return a == b;
  }

  /// Compares two values numerically for relational operators.
  ///
  /// Only numbers are supported. Returns negative if a<b, zero if a==b,
  /// positive if a>b.
  static int _compareValues(Object? a, Object? b) {
    if (a is bool || b is bool || a is! num || b is! num) {
      throw TypeMismatchException('>, <, >=, <=', 'only support numbers');
    }
    final numA = a.toDouble();
    final numB = b.toDouble();
    if (numA.isNaN || numB.isNaN) {
      throw TypeMismatchException('>, <, >=, <=', 'do not support NaN');
    }
    return numA.compareTo(numB);
  }

  // ===========================================================================
  // Logic helpers
  // ===========================================================================

  static bool _evaluateAnd(
    List<JsonLogicRule> operands,
    Map<String, Object?> data,
  ) {
    if (operands.isEmpty) {
      throw InvalidExpressionException('and', 'requires at least 1 argument');
    }
    // Evaluate ALL operands (no short-circuit) so a type error in a later
    // operand still surfaces. Track the answer in a single bool rather than
    // materializing a results list — keeps memory O(1) for huge operand
    // lists.
    var allTrue = true;
    for (final operand in operands) {
      final result = evaluate(operand, data);
      if (result is! bool) {
        throw TypeMismatchException(
          'and',
          'operands must be boolean expressions',
        );
      }
      if (!result) allTrue = false;
    }
    return allTrue;
  }

  static bool _evaluateOr(
    List<JsonLogicRule> operands,
    Map<String, Object?> data,
  ) {
    if (operands.isEmpty) {
      throw InvalidExpressionException('or', 'requires at least 1 argument');
    }
    var anyTrue = false;
    for (final operand in operands) {
      final result = evaluate(operand, data);
      if (result is! bool) {
        throw TypeMismatchException(
          'or',
          'operands must be boolean expressions',
        );
      }
      if (result) anyTrue = true;
    }
    return anyTrue;
  }

  // ===========================================================================
  // String/Array helpers
  // ===========================================================================

  static bool _evaluateIn(InRule rule, Map<String, Object?> data) {
    final needle = evaluate(rule.needle, data);
    if (needle is! String) {
      throw TypeMismatchException('in', 'requires a string needle');
    }
    final haystack = evaluate(rule.haystack, data);
    if (haystack is String) {
      return haystack.contains(needle);
    }
    if (haystack is List) {
      // All elements must be strings (validated via _strictEquals). We check
      // ALL elements even after finding a match to ensure type safety.
      // Track the answer in a single bool to keep memory O(1) for huge
      // haystacks.
      var found = false;
      for (final element in haystack) {
        if (_strictEquals(needle, element)) found = true;
      }
      return found;
    }
    throw TypeMismatchException('in', 'requires a string or array haystack');
  }

  // ===========================================================================
  // Data access helpers
  // ===========================================================================

  static Object? _evaluateVar(VarRule rule, Map<String, Object?> data) {
    final pathValue = evaluate(rule.path, data);
    final path = pathValue == null ? '' : pathValue.toString();

    if (path.isEmpty) {
      throw InvalidExpressionException('var', 'property name is required');
    }

    if (path.contains('.')) {
      throw InvalidExpressionException(
        'var',
        "dots in property names are not supported - '$path'",
      );
    }

    return data.containsKey(path) ? data[path] : null;
  }
}

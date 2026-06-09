/// Base exception for JsonLogic errors.
abstract class JsonLogicException implements Exception {
  JsonLogicException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when an unsupported operator is encountered during parsing.
class UnsupportedOperatorException extends JsonLogicException {
  UnsupportedOperatorException(String operator)
    : super(
        "Unsupported operator: '$operator'. "
        'Try updating to a newer SDK version for possible operator support.',
      );
}

/// Thrown when a type mismatch occurs during evaluation.
class TypeMismatchException extends JsonLogicException {
  TypeMismatchException(String expression, String reason)
    : super(
        "Type mismatch in '$expression': $reason. "
        'Try updating to a newer SDK version for possible type support.',
      );
}

/// Thrown when an expression is structurally invalid.
class InvalidExpressionException extends JsonLogicException {
  InvalidExpressionException(String expression, String reason)
    : super(
        "Invalid expression '$expression': $reason. "
        'Try updating to a newer SDK version for possible expression support.',
      );
}

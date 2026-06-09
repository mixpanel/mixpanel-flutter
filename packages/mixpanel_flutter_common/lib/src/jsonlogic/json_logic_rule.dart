/// Abstract base for all supported JsonLogic operations.
///
/// Each node holds its operands as typed children, making the full rule tree
/// strongly typed after parsing.
///
/// Supported operators (per Event Trigger alignment decision):
/// - Comparison: ===, !==, <, <=, >, >=
/// - Logic: and, or
/// - String/Array: in
/// - Data Access: var
abstract class JsonLogicRule {
  const JsonLogicRule();
}

/// A literal value (string, number, boolean, null, or array of literals).
class LiteralRule extends JsonLogicRule {
  const LiteralRule(this.value);
  final Object? value;
}

// =============================================================================
// Comparison Operations
// =============================================================================

/// Strict equality (===) - no type coercion.
class StrictEqualsRule extends JsonLogicRule {
  const StrictEqualsRule(this.left, this.right);
  final JsonLogicRule left;
  final JsonLogicRule right;
}

/// Strict inequality (!==).
class StrictNotEqualsRule extends JsonLogicRule {
  const StrictNotEqualsRule(this.left, this.right);
  final JsonLogicRule left;
  final JsonLogicRule right;
}

/// Greater than (>).
class GreaterThanRule extends JsonLogicRule {
  const GreaterThanRule(this.left, this.right);
  final JsonLogicRule left;
  final JsonLogicRule right;
}

/// Greater than or equal (>=).
class GreaterThanOrEqualRule extends JsonLogicRule {
  const GreaterThanOrEqualRule(this.left, this.right);
  final JsonLogicRule left;
  final JsonLogicRule right;
}

/// Less than (<) - only 2 arguments supported.
class LessThanRule extends JsonLogicRule {
  const LessThanRule(this.left, this.right);
  final JsonLogicRule left;
  final JsonLogicRule right;
}

/// Less than or equal (<=) - only 2 arguments supported.
class LessThanOrEqualRule extends JsonLogicRule {
  const LessThanOrEqualRule(this.left, this.right);
  final JsonLogicRule left;
  final JsonLogicRule right;
}

// =============================================================================
// Logic Operations
// =============================================================================

/// Logical AND - all operands must evaluate to boolean.
class AndRule extends JsonLogicRule {
  const AndRule(this.operands);
  final List<JsonLogicRule> operands;
}

/// Logical OR - all operands must evaluate to boolean.
class OrRule extends JsonLogicRule {
  const OrRule(this.operands);
  final List<JsonLogicRule> operands;
}

// =============================================================================
// String/Array Operations
// =============================================================================

/// In - checks if needle is in haystack (string or array).
class InRule extends JsonLogicRule {
  const InRule(this.needle, this.haystack);
  final JsonLogicRule needle;
  final JsonLogicRule haystack;
}

// =============================================================================
// Data Access Operations
// =============================================================================

/// Variable access (var) - retrieves value from data using path.
class VarRule extends JsonLogicRule {
  const VarRule(this.path);
  final JsonLogicRule path;
}

// =============================================================================
// Internal Types
// =============================================================================

/// Array literal that may contain rules (evaluated at runtime).
class ArrayRule extends JsonLogicRule {
  const ArrayRule(this.elements);
  final List<JsonLogicRule> elements;
}

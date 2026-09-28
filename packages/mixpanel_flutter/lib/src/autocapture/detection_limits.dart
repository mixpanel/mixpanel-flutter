/// Release-mode safeguards for configuration; assertions also report mistakes
/// during development. Keep sub-millisecond precision inside the valid range.
Duration normalizeTimeWindow(Duration value) {
  const minimum = Duration(milliseconds: 1);
  const maximum = Duration(minutes: 1);
  return value < minimum ? minimum : (value > maximum ? maximum : value);
}

int normalizeClickThreshold(int value) => value.clamp(2, 100);

double normalizeRadius(double value) =>
    value.isFinite ? value.clamp(0, 100000) : 44;

// Duration comparisons cannot be evaluated in const constructor assertions.
// Validate when consumed, retaining const public configuration constructors.
bool validTimeWindow(Duration value) =>
    value >= const Duration(milliseconds: 1) &&
    value <= const Duration(minutes: 1);

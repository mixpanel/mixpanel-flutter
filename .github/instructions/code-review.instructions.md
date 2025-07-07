---
applyTo: "**/*.dart, **/*.java, **/*.swift, **/*.js"
---
# Code Review Guidelines for Mixpanel Flutter SDK

Apply all [general standards](../copilot-instructions.md) with these code review specific checks:

## SDK Consistency Checklist

### Method Implementation Review
```dart
// ✅ CORRECT: Follows SDK patterns
Future<void> newMethod(String required, [Map<String, dynamic>? optional]) async {
  if (!_MixpanelHelper.isValidString(required)) {
    developer.log('`newMethod` failed: required cannot be blank', name: 'Mixpanel');
    return;
  }
  
  await _channel.invokeMethod<void>('newMethod', <String, dynamic>{
    'required': required,
    'optional': optional ?? {},
  });
}

// ❌ INCORRECT: Missing validation, wrong structure
Future<void> newMethod(String required, Map<String, dynamic>? optional) async {
  await _channel.invokeMethod('newMethod', {
    'required': required,
    'optional': optional  // Missing ?? {}
  });
}
```

## Critical Review Points

### 1. Input Validation
- [ ] All string parameters validated with `_MixpanelHelper.isValidString()`
- [ ] Validation happens BEFORE platform channel call
- [ ] Appropriate error logging on validation failure
- [ ] Method returns early on invalid input

### 2. Platform Channel Consistency
- [ ] Method name matches exactly across Dart/Android/iOS/Web
- [ ] Arguments structured as `Map<String, dynamic>`
- [ ] Optional parameters use `?? {}` never pass null
- [ ] Return type is `Future<void>` unless explicitly needed

### 3. Error Handling
- [ ] No exceptions thrown from public methods
- [ ] All errors logged with 'Mixpanel' logger name
- [ ] Platform exceptions caught and logged
- [ ] Silent failure with appropriate logging

### 4. Type Safety
- [ ] DateTime/Uri handled by MixpanelMessageCodec (mobile)
- [ ] Web uses `safeJsify()` for complex types
- [ ] No direct JSON encoding in Dart code
- [ ] Type conversions documented

### 5. Library Metadata
```dart
// Check that tracking methods include:
properties['\$lib_version'] = '2.4.4';
properties['mp_lib'] = 'flutter';
```

## Platform-Specific Reviews

### Android (Java)
- [ ] Uses `JSONObject` for property conversion
- [ ] Proper null checking with TextUtils
- [ ] Result.success(null) for void returns
- [ ] Thread safety for shared resources

### iOS (Swift)
- [ ] Guard statements for validation
- [ ] Proper type conversion with MixpanelType
- [ ] Result(nil) for void returns
- [ ] Memory management for closures

### Web (JavaScript)
- [ ] Uses `safeJsify()` for Dart->JS conversion
- [ ] Proper promise handling
- [ ] No synchronous operations
- [ ] CDN script loaded check

## Test Coverage Review
- [ ] Positive test case with valid inputs
- [ ] Validation failure test cases
- [ ] Empty string and whitespace validation tests
- [ ] Optional parameter tests (null and empty map)
- [ ] Platform channel verification with `isMethodCall`

## Documentation Review
- [ ] Public methods have dartdoc comments
- [ ] Parameter constraints documented
- [ ] Example usage provided for complex methods
- [ ] Platform differences noted if any

## Security Considerations
- [ ] No sensitive data in error logs
- [ ] Input sanitization for user data
- [ ] No hardcoded secrets or keys
- [ ] Safe type conversions

## Performance Review
- [ ] Async/await used appropriately
- [ ] No blocking operations
- [ ] Efficient data structures
- [ ] Minimal platform channel calls

## Common Rejection Reasons

### 🚫 Missing Validation
```dart
// REJECT: No validation
Future<void> track(String eventName) async {
  await _channel.invokeMethod<void>('track', {'eventName': eventName});
}
```

### 🚫 Throwing Exceptions
```dart
// REJECT: Throws exception
Future<void> track(String eventName) async {
  if (eventName.isEmpty) {
    throw ArgumentError('eventName cannot be empty');  // NO!
  }
}
```

### 🚫 Inconsistent Naming
```dart
// REJECT: Method name mismatch
await _channel.invokeMethod<void>('trackEvent', args);  // Should be 'track'
```

### 🚫 Null Parameters
```dart
// REJECT: Passing null
'properties': properties,  // Should be: properties ?? {}
```

## Quick Review Commands

For reviewing changes:
```bash
# Check for validation patterns
grep -n "isValidString" [file]

# Verify platform channel calls
grep -n "invokeMethod" [file]

# Check error handling
grep -n "developer.log" [file]

# Find missing null safety
grep -n "?? {}" [file]
```

## Approval Criteria

✅ **Approve if:**
- Follows all SDK patterns consistently
- Includes comprehensive tests
- Has appropriate documentation
- Handles errors gracefully
- Maintains backward compatibility

🔄 **Request changes if:**
- Missing input validation
- Inconsistent with SDK patterns
- Lacks test coverage
- Could throw exceptions
- Breaks existing API contracts

❌ **Reject if:**
- Security vulnerabilities
- Breaking changes without version bump
- Fundamentally wrong patterns
- No tests provided
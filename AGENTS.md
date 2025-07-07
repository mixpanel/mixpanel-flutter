# Mixpanel Flutter SDK AI Agent Instructions

## Identity

You are an autonomous software engineering agent working on the official Mixpanel Flutter SDK. You execute tasks independently in a cloud environment, producing complete, tested, PR-ready changes that maintain cross-platform compatibility (iOS, Android, Web) and follow established SDK patterns.

## Project Overview

This is the official Mixpanel Flutter SDK - a Flutter plugin providing analytics tracking capabilities across iOS, Android, and Web platforms. The plugin wraps native Mixpanel SDKs and provides a unified Dart API.

### Key Technologies
- **Flutter/Dart**: Core SDK implementation
- **Platform Channels**: Communication between Dart and native code
- **Native SDKs**: Mixpanel-Android (v8.0.3), Mixpanel-Swift (v5.0.0), Mixpanel-JS (CDN)
- **Custom Serialization**: MixpanelMessageCodec for complex types
- **Testing**: Flutter unit tests with mocked platform channels

### Architecture Summary
- **lib/**: Dart SDK implementation with platform channel interface
- **android/**: Java wrapper around Mixpanel Android SDK
- **ios/**: Swift wrapper around Mixpanel iOS SDK
- **example/**: Integration test app demonstrating all features
- **test/**: Comprehensive unit tests

For detailed architecture, see `.claude/context/architecture/` (if available).

## AI Ecosystem References

This project maintains comprehensive AI assistance configuration. You MUST respect all patterns documented in:

1. **`CLAUDE.md`** - Core patterns, workflows, and project context
2. **`.cursor/rules/`** - Behavioral rules for code generation (if present)
3. **`.github/copilot-instructions.md`** - Universal coding standards and conventions
4. **`.github/instructions/`** - Specialized instructions for testing and code review

Always check these files when uncertain about patterns or conventions. They contain the team's accumulated knowledge and prevent common errors.

## Environment Setup

```bash
# Install Flutter dependencies
flutter pub get

# Install example app dependencies
cd example && flutter pub get && cd ..

# Verify environment
flutter doctor
flutter analyze
flutter test

# Additional tools for validation
dart format --set-exit-if-changed .
```

### Platform-Specific Setup
- **Android**: Requires Java 17+ for builds
- **iOS**: Requires Xcode and CocoaPods
- **Web**: No additional setup required

## Development Workflow

### Before Making Changes
1. Read `CLAUDE.md` for project-specific patterns
2. Check `.github/copilot-instructions.md` for universal standards
3. Review existing implementations in similar methods
4. Run `flutter test` to ensure starting from clean state

### While Developing
1. **ALWAYS validate string inputs** using `_MixpanelHelper.isValidString()`
2. **Follow platform channel pattern exactly**:
   ```dart
   await _channel.invokeMethod<void>('methodName', <String, dynamic>{
     'param1': value1,
     'param2': value2 ?? {},  // Never pass null
   });
   ```
3. **Handle errors silently** with logging:
   ```dart
   developer.log('`methodName` failed: reason', name: 'Mixpanel');
   ```
4. **Include library metadata** in all tracking calls
5. **Write tests immediately** after implementation

### Validation Requirements
- [ ] All tests pass: `flutter test`
- [ ] Static analysis clean: `flutter analyze`
- [ ] Code formatted: `dart format .`
- [ ] No security violations (check `.github/copilot-instructions.md`)
- [ ] Platform channel naming matches exactly
- [ ] Example app updated if adding features
- [ ] Version consistency across all files

## Common Tasks

### Adding New SDK Methods
Follow the 5-step implementation process:
1. Define method in `lib/mixpanel_flutter.dart` with validation
2. Add platform channel invocation with standard arguments
3. Implement handlers:
   - Android: `MixpanelFlutterPlugin.java`
   - iOS: `SwiftMixpanelFlutterPlugin.swift`
   - Web: `mixpanel_flutter_web.dart`
4. Add tests to `test/mixpanel_flutter_test.dart`
5. Add example usage in `example/lib/`

See `.github/prompts/add-analytics-method.prompt.md` for detailed steps.

### Implementing Platform Handlers

#### Android (Java)
```java
case "methodName":
  String param = call.argument("param");
  if (TextUtils.isEmpty(param)) {
    result.error("INVALID_ARGUMENT", "param cannot be empty", null);
    return;
  }
  // Implementation using Mixpanel Android SDK
  result.success(null);
  break;
```

#### iOS (Swift)
```swift
case "methodName":
  guard let args = call.arguments as? [String: Any],
        let param = args["param"] as? String,
        !param.isEmpty else {
    result(FlutterError(code: "INVALID_ARGUMENT", 
                       message: "param cannot be empty", 
                       details: nil))
    return
  }
  // Implementation using Mixpanel iOS SDK
  result(nil)
```

#### Web (Dart/JS)
```dart
Future<void> methodName(String param, Map<String, dynamic>? properties) async {
  if (!_MixpanelHelper.isValidString(param)) {
    developer.log('`methodName` failed: param cannot be blank', name: 'Mixpanel');
    return;
  }
  _mixpanel.methodName(param, safeJsify(properties ?? {}));
}
```

### Writing Tests
Always follow the SDK test pattern:
```dart
test('methodName validates input and calls platform channel', () async {
  await mixpanel.methodName('valid', properties: {'key': 'value'});
  expect(
    methodCall,
    isMethodCall(
      'methodName',
      arguments: <String, dynamic>{
        'param': 'valid',
        'properties': {'key': 'value'},
      },
    ),
  );
});

test('methodName fails silently with invalid input', () async {
  await mixpanel.methodName('', properties: {'key': 'value'});
  expect(methodCall, isNull);
});
```

### Bug Fixes
1. Write failing test demonstrating the bug
2. Fix with minimal changes following existing patterns
3. Ensure all existing tests still pass
4. Update example app if behavior changes

## Task Execution Instructions

### Planning Phase
Before writing any code:
1. Identify all files that need modification
2. Check similar existing implementations
3. Review validation patterns in affected code
4. Plan test cases (success, validation, edge cases)

### Implementation Phase
1. Start with Dart interface and validation
2. Implement platform handlers one at a time
3. Run tests after each platform implementation
4. Test in example app on actual devices/simulators
5. Ensure cross-platform consistency

### PR Preparation
Your PR should include:
- **Title**: `[Component] Brief description` (e.g., `[SDK] Add trackPurchase method`)
- **Description**:
  ```markdown
  ## Summary
  Brief description of changes
  
  ## Changes
  - Added `trackPurchase` method to Mixpanel class
  - Implemented Android, iOS, and Web handlers
  - Added comprehensive unit tests
  - Updated example app with purchase tracking demo
  
  ## Testing
  - [ ] Unit tests pass
  - [ ] Tested on Android device/emulator
  - [ ] Tested on iOS device/simulator
  - [ ] Tested on Web browser
  
  ## Notes
  Any implementation decisions or trade-offs
  ```

## Code Standards

### Critical Patterns (from all AI systems)
1. **Input Validation**: ALWAYS validate before platform calls
2. **Error Handling**: Silent failure with logging, no exceptions
3. **Return Types**: All public methods return `Future<void>`
4. **Null Safety**: Use `?? {}` for optional maps, never pass null
5. **Library Metadata**: Include version and library identifier

### Naming Conventions
- Methods: `camelCase` with verb prefixes
- Parameters: Descriptive (`eventName`, `distinctId`, `properties`)
- Platform methods: Must match exactly across all platforms
- Test names: `should [behavior] when [condition]`

### Testing Requirements
- Every method needs success and failure tests
- Use `isMethodCall` matcher for platform verification
- Test validation for empty strings and whitespace
- Include edge cases and type conversions

### Security Patterns
- Never log sensitive user data
- Validate all external inputs
- Sanitize before passing to native platforms
- No hardcoded secrets or keys

## Debugging Instructions

If you encounter issues:
1. Check existing similar implementations first
2. Verify platform channel method names match exactly
3. Ensure validation happens before platform calls
4. Confirm test patterns match existing tests
5. Run example app to verify actual behavior

Common issues:
- **Platform channel not found**: Method name mismatch
- **Null pointer exceptions**: Missing `?? {}` for optional parameters
- **Test failures**: Wrong argument structure in `isMethodCall`
- **Web compilation errors**: Missing `safeJsify()` for complex types

## Optimal Task Types

I excel at these task categories:

### 1. Feature Implementation
- Adding new tracking methods following patterns
- Implementing across all platforms consistently
- Creating comprehensive test coverage
Example: "Add group analytics methods for tracking team usage"

### 2. Test Generation
- Adding tests for untested methods
- Increasing code coverage systematically
- Creating edge case scenarios
Example: "Add comprehensive tests for all People methods"

### 3. Platform Consistency
- Ensuring methods work identically across platforms
- Fixing platform-specific bugs
- Standardizing error handling
Example: "Ensure date handling is consistent across iOS/Android/Web"

### 4. Documentation
- Adding dartdoc comments to public APIs
- Creating example implementations
- Updating README with new features
Example: "Document all public methods with usage examples"

### Task Anti-Patterns
I'm less effective at:
- Making architecture decisions without context
- Performance optimization without metrics
- UI/UX decisions in the example app
- Debugging issues without clear reproduction steps

## Notes

- This SDK prioritizes stability and consistency over innovation
- Every change must maintain backward compatibility
- Platform parity is critical - features must work on all platforms
- When uncertain, check how similar methods are implemented
- The example app serves as both documentation and integration test

Remember: You're maintaining an official SDK used by thousands of apps. Reliability, consistency, and thorough testing are paramount.
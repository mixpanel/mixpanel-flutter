# Mixpanel Flutter SDK - Copilot Agent Guide

> Complete operational guide for working efficiently with the Mixpanel Flutter SDK codebase.

## Repository Overview

**What**: Official Flutter SDK for Mixpanel Analytics - wraps native iOS/Android/Web SDKs with unified Dart API
**Size**: ~25 source files, 1.4GB total (includes dependencies and build artifacts)
**Languages**: Dart (SDK), Java (Android), Swift (iOS), JavaScript (Web)
**Runtime**: Flutter 3.16.0, Dart 3.2.0, Java 17, Swift 5.0

## Quick Start - Essential Commands

**ALWAYS run these commands in order. Commands must succeed before proceeding.**

### 1. Install Dependencies (REQUIRED FIRST)
```bash
# From project root - ALWAYS run this first
flutter pub get

# For example app (if working with integration tests)
cd example && flutter pub get && cd ..
```
**Time**: ~30 seconds. **Must complete** before any other command.

### 2. Run Tests
```bash
# Run all unit tests
flutter test
```
**Time**: ~5 seconds. **Expected**: All tests pass. The SDK has comprehensive test coverage.

### 3. Lint/Analyze Code
```bash
# Analyze Dart code (will show ~70 info-level warnings - this is normal)
flutter analyze --no-pub --no-current-package --no-fatal-infos lib
```
**Expected warnings**: Style suggestions (unnecessary_this, prefer_const, etc.) - NOT errors.
**Time**: <1 second

### 4. Build Integration Tests
```bash
# Android (from example directory)
cd example && flutter build apk --debug

# iOS (from example directory, macOS only)
cd example && flutter build ios --debug --simulator --no-codesign
```
**Android Time**: ~3 minutes first run, ~1 minute incremental
**iOS Time**: ~5 minutes (requires CocoaPods: `cd example/ios && pod repo update`)

## Project Structure

### Core SDK Files
```
lib/
├── mixpanel_flutter.dart          # Main SDK - Primary API
├── mixpanel_flutter_web.dart      # Web implementation
├── codec/
│   └── mixpanel_message_codec.dart # Custom type serialization
└── web/
    └── mixpanel_js_bindings.dart   # JavaScript interop
```

### Native Platform Code
```
android/
├── build.gradle                    # Android config (SDK 34, Java 17)
└── src/main/java/com/mixpanel/mixpanel_flutter/
    ├── MixpanelFlutterPlugin.java  # Android platform channel
    ├── MixpanelMessageCodec.java   # Type serialization
    └── MixpanelFlutterHelper.java  # Validation helpers

ios/
├── mixpanel_flutter.podspec        # iOS package (Mixpanel-swift 5.1.0)
└── Classes/
    ├── SwiftMixpanelFlutterPlugin.swift # iOS platform channel
    └── MixpanelTypeHandler.swift        # Type serialization
```

### Tests
```
test/
├── mixpanel_flutter_test.dart      # Main test suite
└── mixpanel_flutter_web_unit_test.dart # Web-specific tests
```

### Configuration Files
- `pubspec.yaml` - Flutter package config, dependencies
- `analysis_options.yaml` - Lints (uses flutter_lints package)
- `.github/workflows/flutter.yml` - CI pipeline (see below)

## Continuous Integration

The GitHub Actions workflow runs **3 jobs** on every PR:

### 1. test-main-code (macOS, ~2 min)
```bash
flutter pub get
flutter test
flutter analyze --no-pub --no-current-package --no-fatal-infos lib
```

### 2. test-android-integration (macOS, ~3 min)
```bash
cd example && flutter build apk
```

### 3. test-ios-integration (macOS, ~5 min)
```bash
cd example
flutter clean
flutter pub get
cd ios && pod repo update && cd ..
flutter build ios --debug --simulator --no-codesign
```

**To replicate CI locally**, run all three command sequences above in order.

## Common Build Issues & Solutions

### Issue: "flutter: command not found"
- **Fix**: Install Flutter 3.16.0 from https://flutter.dev/docs/get-started/install

### Issue: Android build fails with SDK version error
- **Expected**: Warning about SDK 34 is normal (plugin requires it, example uses 33)
- **Fix**: The build will auto-download SDK 33 and succeed

### Issue: iOS build fails with CocoaPods error
- **Fix**: Run `cd example/ios && pod repo update` before building

### Issue: "Gradle task assembleDebug" timeout
- **Expected**: First Android build takes 2-3 minutes
- **Solution**: Use `initial_wait: 180` for async commands

### Issue: Tests fail after code changes
- **Cause**: Platform channel method name mismatch
- **Fix**: Ensure method names match exactly in Dart + Java/Swift + Web

## Critical Coding Patterns

**ALWAYS follow these patterns when modifying SDK code:**

### 1. Input Validation Pattern (MANDATORY)
```dart
Future<void> methodName(String param) async {
  if (!_MixpanelHelper.isValidString(param)) {
    developer.log('`methodName` failed: param cannot be blank', name: 'Mixpanel');
    return;  // Fail silently - NEVER throw exceptions
  }
  await _channel.invokeMethod<void>('methodName', {'param': param});
}
```

### 2. Platform Channel Rules
- Method names MUST match exactly: Dart ↔ Java/Swift/Web
- Arguments ALWAYS as `Map<String, dynamic>`
- Optional maps use `?? {}` - NEVER pass null
- All methods return `Future<void>` for consistency

### 3. Type Handling
- **Mobile**: MixpanelMessageCodec auto-handles DateTime/Uri
- **Web**: Use `safeJsify()` for complex types

### 4. Testing Requirements
Every method MUST have tests:
```dart
test('methodName should invoke platform method', () async {
  await mixpanel.methodName('param');
  expect(methodCalls, hasLength(1));
  expect(methodCalls[0], isMethodCall('methodName', 
    arguments: {'param': 'param'}));
});

test('methodName should fail silently on invalid input', () async {
  await mixpanel.methodName('');  // Empty string
  expect(methodCalls, isEmpty);  // No platform call made
});
```

## Adding New Features - Checklist

When adding a new SDK method:
1. ✅ Add to `lib/mixpanel_flutter.dart` with validation
2. ✅ Implement in `android/.../MixpanelFlutterPlugin.java`
3. ✅ Implement in `ios/.../SwiftMixpanelFlutterPlugin.swift`
4. ✅ Implement in `lib/mixpanel_flutter_web.dart`
5. ✅ Add tests to `test/mixpanel_flutter_test.dart`
6. ✅ Run `flutter test` - MUST pass all tests
7. ✅ Run `flutter analyze` - check for new errors
8. ✅ Build example app to verify integration

## File Organization

**NEVER modify**:
- `build/` - Build artifacts (gitignored)
- `.dart_tool/` - Flutter tooling cache
- `example/pubspec.lock` - Auto-generated

**Config files to update when**:
- `pubspec.yaml` - Adding dependencies only
- `ios/mixpanel_flutter.podspec` - iOS SDK version bump
- `android/build.gradle` - Android SDK version bump

## Performance Notes

- `flutter pub get`: 30 seconds
- `flutter test`: 5 seconds
- `flutter analyze`: <1 second
- Example Android build: 3 min (first), 1 min (incremental)
- Example iOS build: 5 min (requires `pod repo update`)

## Dependencies

**Production**:
- Mixpanel Android SDK 8.2.0 (in `android/build.gradle`)
- Mixpanel-swift 5.1.0 (in `ios/mixpanel_flutter.podspec`)
- Mixpanel JS (loaded from CDN in web/index.html)

**Dev**:
- flutter_lints 3.0.0 - Linting rules
- flutter_test - Testing framework

## Validation Checklist Before Committing

1. ✅ `flutter pub get` - Must succeed
2. ✅ `flutter test` - All tests pass
3. ✅ `flutter analyze lib` - No new errors (~70 infos OK)
4. ✅ Check method names match across all platforms
5. ✅ Verify input validation exists for all public methods
6. ✅ Confirm tests added for new functionality

**Trust these instructions.** Only search/explore if information is incomplete or incorrect. This guide covers 90% of common scenarios.
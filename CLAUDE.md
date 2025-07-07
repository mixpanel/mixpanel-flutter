# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the official Mixpanel Flutter SDK - a Flutter plugin that provides analytics tracking capabilities for Flutter applications across iOS, Android, and Web platforms. The plugin wraps the native Mixpanel SDKs and provides a unified Dart API.

## Core Patterns & Conventions

### Method Naming
- All Dart methods use camelCase: `track`, `trackWithGroups`, `registerSuperProperties`
- Platform channel method names must match exactly between Dart and native code
- Getter methods use `get` prefix: `getPeople()`, `getGroup()`

### Input Validation Pattern
```dart
// Always validate string inputs before platform calls
if (_MixpanelHelper.isValidString(eventName)) {
  await _channel.invokeMethod<void>('track', args);
} else {
  developer.log('`track` failed: eventName cannot be blank', name: 'Mixpanel');
}
```

### Platform Channel Pattern
```dart
// Standard invocation pattern for all methods
Future<void> methodName(parameters) async {
  await _channel.invokeMethod<void>('methodName', <String, dynamic>{
    'param1': value1,
    'param2': value2 ?? {}, // Use ?? {} for optional maps
  });
}
```

## Key Architecture

### Platform Channel Architecture
- The plugin uses Flutter's platform channel mechanism to communicate between Dart and native code
- Custom `MixpanelMessageCodec` handles serialization of complex data types between platforms
- Each platform (iOS, Android, Web) has its own implementation that wraps the respective Mixpanel SDK

### Core Classes
- `Mixpanel` - Main singleton class for tracking events and managing the SDK
- `People` - User profile management (accessible via `mixpanel.getPeople()`)
- `MixpanelGroup` - Group analytics management (accessible via `mixpanel.getGroup()`)

### Platform Dependencies
- Android: Mixpanel Android SDK v8.0.3
- iOS: Mixpanel-swift v5.0.0
- Web: Mixpanel JavaScript library (loaded from CDN)

## Development Commands

```bash
# Install dependencies
flutter pub get

# Run tests
flutter test

# Run the example app (from project root)
cd example
flutter run

# Build for specific platform
flutter build apk      # Android
flutter build ios      # iOS
flutter build web      # Web

# Analyze code
flutter analyze

# Format code
dart format .

# Generate documentation
flutter pub run dartdoc
```

## Testing Strategy

- Unit tests are in `test/mixpanel_flutter_test.dart`
- The example app serves as an integration test suite with pages for each feature
- Platform-specific functionality should be tested through the example app on each platform

## Release Process

Use the release script: `python tool/release.py`

This handles version bumping, changelog updates, and tagging.

## Important Implementation Notes

### Web Platform
- Web implementation requires adding Mixpanel JS to the HTML header
- The plugin dynamically loads the Mixpanel JavaScript library
- Web-specific implementation is in `lib/mixpanel_flutter_web.dart`

### Message Codec
- Custom codec is required to handle DateTime objects and other complex types
- Implementations: `MixpanelMessageCodec.java` (Android) and `MixpanelTypeHandler.swift` (iOS)

### API Design
- All methods return Futures for consistency across platforms
- Super properties persist across app launches
- Groups and user profiles are managed through separate accessor methods

## Essential Implementation Patterns

### Adding New Features
1. Define method in `lib/mixpanel_flutter.dart` with validation
2. Add platform channel invocation with standard argument structure
3. Implement handlers in:
   - `MixpanelFlutterPlugin.java` (Android)
   - `SwiftMixpanelFlutterPlugin.swift` (iOS)
   - `mixpanel_flutter_web.dart` (Web)
4. Add tests to `test/mixpanel_flutter_test.dart`
5. Add example usage in `example/lib/`

### Type Handling
- **DateTime/Uri**: Automatically serialized by `MixpanelMessageCodec` on mobile
- **Web**: Use `safeJsify()` for JavaScript compatibility
- **Complex objects**: Convert to `Map<String, dynamic>` first

### Error Handling Philosophy
- Input validation prevents crashes
- Methods fail silently with logging
- No exceptions thrown to calling code
- Platform errors caught and logged

### Library Metadata
All events automatically include:
```dart
'\$lib_version': '2.4.4',  // Current SDK version
'mp_lib': 'flutter',       // Library identifier
```

### Testing Pattern
```dart
test('method behavior', () async {
  await mixpanel.methodName('param');
  expect(
    methodCall,
    isMethodCall(
      'methodName',
      arguments: <String, dynamic>{'param': 'value'},
    ),
  );
});
```

## Platform-Specific Notes

### Android
- Lazy initialization to prevent ANR
- Uses `JSONObject` for property conversion
- Helper class for property merging

### iOS
- Uses `MixpanelType` for type conversion
- Swift implementation with type safety
- Guard statements for validation

### Web
- Requires mixpanel.js in HTML header
- JavaScript interop with `@JS` annotations
- Dynamic type conversion with `jsify()`

## Quick Reference

For detailed patterns and workflows, see:
- `.claude/context/discovered-patterns.md` - All coding patterns
- `.claude/context/architecture/system-design.md` - System architecture
- `.claude/context/workflows/` - Development workflows
- `.claude/context/technologies/` - Technology deep dives
# Codebase Map

## Project Structure Overview

The Mixpanel Flutter SDK is a comprehensive Flutter plugin that provides analytics tracking capabilities across iOS, Android, and Web platforms. It follows Flutter's federated plugin architecture, with platform-specific implementations wrapping native Mixpanel SDKs.

## Directory Hierarchy

```
mixpanel-flutter/
├── lib/                           # Dart/Flutter public API
│   ├── mixpanel_flutter.dart     # Main entry point & core classes
│   ├── mixpanel_flutter_web.dart # Web platform implementation
│   ├── codec/
│   │   └── mixpanel_message_codec.dart # Custom serialization codec
│   └── web/
│       └── mixpanel_js_bindings.dart   # JavaScript interop bindings
├── android/                       # Android platform channel
│   └── src/main/java/com/mixpanel/mixpanel_flutter/
│       ├── MixpanelFlutterPlugin.java    # Main plugin class
│       ├── MixpanelFlutterHelper.java    # Helper utilities
│       └── MixpanelMessageCodec.java     # Android codec implementation
├── ios/                           # iOS platform channel
│   └── Classes/
│       ├── SwiftMixpanelFlutterPlugin.swift # Main plugin class
│       └── MixpanelTypeHandler.swift        # iOS type handling
├── example/                       # Example application
│   ├── lib/
│   │   ├── main.dart             # Example app entry
│   │   └── [feature]_page.dart   # Feature demonstration pages
│   ├── android/                  # Android example config
│   ├── ios/                      # iOS example config
│   └── web/                      # Web example config
├── test/                         # Unit tests
│   ├── mixpanel_flutter_test.dart          # Core functionality tests
│   └── mixpanel_flutter_web_unit_test.dart # Web-specific tests
├── tool/                         # Development tools
│   └── release.py               # Automated release script
└── docs/                        # Generated API documentation

## Key Entry Points

- **lib/mixpanel_flutter.dart**: Main public API entry point
  - Exports `Mixpanel` singleton class for event tracking
  - Exports `People` class for user profile management
  - Exports `MixpanelGroup` class for group analytics
  - Defines platform channel interface

- **android/src/.../MixpanelFlutterPlugin.java**: Android platform entry
  - Registers with Flutter engine
  - Implements MethodChannel handler
  - Delegates to native Mixpanel Android SDK

- **ios/Classes/SwiftMixpanelFlutterPlugin.swift**: iOS platform entry
  - Registers with Flutter engine
  - Implements FlutterMethodChannel handler
  - Delegates to native Mixpanel-swift SDK

- **lib/mixpanel_flutter_web.dart**: Web platform entry
  - Implements platform interface for web
  - Uses JavaScript interop to call Mixpanel JS library
  - Handles web-specific initialization

## Configuration Files

- **pubspec.yaml**: Flutter package definition
  - Current version: 2.4.4
  - Dependencies: flutter, flutter_web_plugins, js
  - Platform support declarations

- **android/build.gradle**: Android build configuration
  - compileSdk: 34
  - minSdk: 21
  - Mixpanel Android SDK: v8.2.0

- **ios/mixpanel_flutter.podspec**: iOS pod configuration
  - iOS deployment target: 12.0
  - Mixpanel-swift dependency: ~> 5.1.0
  - Swift version: 5.0

- **analysis_options.yaml**: Dart static analysis rules
  - Enforces Flutter style guide
  - Custom linting rules

## Documentation Located

- **README.md**: Quick start guide with installation instructions
- **CHANGELOG.md**: Version history and migration guides
- **CLAUDE.md**: AI assistant context and guidelines
- **example/README.md**: Example app usage instructions
- **docs/**: Auto-generated dartdoc API reference

## Build & Release Infrastructure

- **.github/workflows/flutter.yml**: CI workflow for tests
- **.github/workflows/release.yml**: Automated release workflow
- **tool/release.py**: Python script for version management
- **Makefile**: Common development commands

## Platform-Specific Implementation Details

### Android
- Uses Java for platform channel implementation
- Custom `MixpanelMessageCodec` for type serialization
- Helper class for common operations
- Requires Android API 21+ (Android 5.0)

### iOS
- Uses Swift for platform channel implementation
- Custom `MixpanelTypeHandler` for type conversion
- Direct integration with Mixpanel-swift pod
- Requires iOS 12.0+

### Web
- Pure Dart implementation using JS interop
- Dynamically loads Mixpanel JS library from CDN
- Custom `safeJsify` for safe object conversion
- Requires adding script tag to HTML
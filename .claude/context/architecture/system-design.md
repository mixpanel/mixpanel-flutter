# System Architecture

## Overview

The Mixpanel Flutter SDK implements a federated plugin architecture that provides a unified Dart API while leveraging platform-specific native SDKs. This design ensures optimal performance and feature parity across iOS, Android, and Web platforms.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Dart API Layer                           │
│  (Mixpanel, People, MixpanelGroup classes)                 │
│  - Public API methods                                       │
│  - Input validation                                         │
│  - Platform abstraction                                     │
├─────────────────────────────────────────────────────────────┤
│                Platform Channel Layer                        │
│  - MethodChannel with custom MixpanelMessageCodec          │
│  - Type serialization/deserialization                      │
│  - Platform detection (kIsWeb)                             │
├─────────────────────┬───────────────┬──────────────────────┤
│     Android         │     iOS       │       Web            │
│  Implementation     │ Implementation│  Implementation      │
├─────────────────────┼───────────────┼──────────────────────┤
│  Java Plugin        │ Swift Plugin  │  Dart/JS Interop    │
│  - JSONObject       │ - Dictionary  │  - jsify()          │
│  - Type conversion  │ - Type handler│  - safeJsify()      │
├─────────────────────┼───────────────┼──────────────────────┤
│ Mixpanel Android    │ Mixpanel-swift│  Mixpanel JS        │
│    SDK v8.0.3       │   SDK v5.0.0  │   (CDN loaded)      │
└─────────────────────┴───────────────┴──────────────────────┘
                              ↓
                    Mixpanel Analytics Servers
```

## Request Flow Example: Track Event

### 1. Dart API Call
```dart
// User code
await mixpanel.track('Button Clicked', properties: {
  'button_name': 'purchase',
  'timestamp': DateTime.now(),
});
```

### 2. Validation & Channel Invocation
```dart
// In lib/mixpanel_flutter.dart
Future<void> track(String eventName, {Map<String, dynamic>? properties}) async {
  if (_MixpanelHelper.isValidString(eventName)) {
    await _channel.invokeMethod<void>('track', <String, dynamic>{
      'eventName': eventName,
      'properties': properties ?? {},
    });
  } else {
    developer.log('`track` failed: eventName cannot be blank', name: 'Mixpanel');
  }
}
```

### 3. Platform-Specific Handling

#### Android Path
```java
// In MixpanelFlutterPlugin.java
case "track":
    eventName = call.argument("eventName");
    properties = call.argument("properties");
    JSONObject jsonObject = MixpanelFlutterHelper.toJSONObject(properties);
    mixpanel.track(eventName, jsonObject);
    result.success(null);
    break;
```

#### iOS Path
```swift
// In SwiftMixpanelFlutterPlugin.swift
case "track":
    guard let arguments = call.arguments as? [String: Any] else { return }
    let eventName = arguments["eventName"] as! String
    if let properties = arguments["properties"] as? [String: Any] {
        let mpProperties = convertToMixpanelTypes(properties)
        Mixpanel.mainInstance().track(event: eventName, properties: mpProperties)
    }
```

#### Web Path
```dart
// In mixpanel_flutter_web.dart
@override
Future<void> track(String eventName, Map<String, dynamic> properties) async {
  var trackedProperties = safeJsify(properties);
  mixpanelJs.track(eventName, trackedProperties);
}
```

## Initialization Flow

### 1. Static Factory Method
```dart
// Application code
final mixpanel = await Mixpanel.init(
  'YOUR_TOKEN',
  trackAutomaticEvents: true,
  superProperties: {'platform': 'mobile'},
);
```

### 2. Platform Initialization

#### Mobile Platforms (Android/iOS)
1. Create platform channel with custom codec
2. Invoke 'initialize' method with configuration
3. Native side creates/configures SDK instance
4. Store reference for subsequent calls

#### Web Platform
1. Check for mixpanel.js presence in window
2. Initialize with token and config
3. Set super properties if provided
4. Configure automatic tracking

## Data Serialization Strategy

### Custom Message Codec (Mobile)
Handles special types not supported by standard codec:
```dart
// From mixpanel_message_codec.dart
void writeValue(WriteBuffer buffer, dynamic value) {
  if (value is DateTime) {
    buffer.putUint8(_typeDateTime);
    buffer.putInt64(value.millisecondsSinceEpoch);
  } else if (value is Uri) {
    buffer.putUint8(_typeUri);
    writeValue(buffer, value.toString());
  } else {
    super.writeValue(buffer, value);
  }
}
```

### Web Type Conversion
Ensures JavaScript compatibility:
```dart
dynamic safeJsify(Object value) {
  if (value is Map<dynamic, dynamic>) {
    value = JsLinkedHashMap.from(value);
  }
  var args = jsify(value);
  return args;
}
```

## Component Responsibilities

### Dart API Layer
- **Input validation**: Ensures non-empty strings for required parameters
- **Platform abstraction**: Hides platform differences from consumers
- **Type safety**: Provides strongly-typed Dart interfaces
- **Documentation**: Comprehensive API documentation

### Platform Channel Layer
- **Serialization**: Converts Dart objects to platform-compatible formats
- **Method routing**: Maps Dart method calls to native implementations
- **Error propagation**: Surfaces platform errors to Dart layer
- **Custom codec**: Handles DateTime and Uri types

### Native Implementation Layer
- **SDK integration**: Wraps native Mixpanel SDKs
- **Type conversion**: Converts between Flutter and native types
- **Platform optimization**: Uses platform-specific features
- **Lifecycle management**: Handles app lifecycle events

## Architectural Principles

### 1. **Separation of Concerns**
Each layer has clear responsibilities with minimal overlap. The Dart layer knows nothing about native implementations.

### 2. **Platform Parity**
All platforms expose the same Dart API, ensuring consistent behavior across iOS, Android, and Web.

### 3. **Type Safety**
Custom codecs and type handlers ensure type safety across language boundaries.

### 4. **Performance Optimization**
- Lazy initialization on Android to prevent ANR
- Direct native SDK calls for minimal overhead
- Asynchronous operations throughout

### 5. **Fail-Safe Design**
- Invalid inputs logged but don't crash
- Platform errors caught and surfaced
- Graceful degradation on web if JS not loaded

## Cross-Cutting Concerns

### Error Handling
- Input validation at Dart layer
- Platform-specific error handling
- Consistent error logging with 'Mixpanel' tag

### Metadata Injection
All events automatically include:
- `$lib_version`: SDK version
- `mp_lib`: Library identifier
- Platform-specific metadata

### Configuration
- Token-based initialization
- Optional automatic event tracking
- Super properties for all events
- Platform-specific config options

## Extension Points

### Adding New Methods
1. Add method to Dart API with validation
2. Add platform channel invocation
3. Implement in each platform handler
4. Add type conversions if needed
5. Write tests for all platforms

### Supporting New Types
1. Extend MixpanelMessageCodec
2. Add type handlers for iOS/Android
3. Update safeJsify for web
4. Test serialization round-trip
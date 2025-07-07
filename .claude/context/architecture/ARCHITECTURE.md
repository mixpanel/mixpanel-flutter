# Mixpanel Flutter SDK Architecture

## Overview

The Mixpanel Flutter SDK is a cross-platform analytics plugin that provides a unified Dart API for tracking events and managing user profiles across iOS, Android, and Web platforms. The SDK uses Flutter's platform channel mechanism to communicate between Dart code and native platform implementations.

## Architecture Layers

### 1. Dart API Layer (`lib/mixpanel_flutter.dart`)

The main entry point providing a unified interface across all platforms:

```dart
class Mixpanel {
  static final MethodChannel _channel = kIsWeb
      ? const MethodChannel('mixpanel_flutter')
      : const MethodChannel('mixpanel_flutter', StandardMethodCodec(MixpanelMessageCodec()));
      
  // Core tracking method
  Future<void> track(String eventName, {Map<String, dynamic>? properties}) async {
    await _channel.invokeMethod<void>('track', {
      'eventName': eventName, 
      'properties': _MixpanelHelper.ensureSerializableProperties(properties)
    });
  }
}
```

Key components:
- **Mixpanel**: Main singleton class for event tracking
- **People**: User profile management (accessed via `mixpanel.getPeople()`)
- **MixpanelGroup**: Group analytics management (accessed via `mixpanel.getGroup()`)

### 2. Platform Channel & Serialization

#### Custom Message Codec (`lib/codec/mixpanel_message_codec.dart`)

Handles serialization of complex types between Dart and native platforms:

```dart
class MixpanelMessageCodec extends StandardMessageCodec {
  static const int _kDateTime = 128;
  static const int _kUri = 129;
  
  @override
  void writeValue(WriteBuffer buffer, dynamic value) {
    if (value is DateTime) {
      buffer.putUint8(_kDateTime);
      buffer.putInt64(value.millisecondsSinceEpoch);
    } else if (value is Uri) {
      buffer.putUint8(_kUri);
      final bytes = utf8.encoder.convert(value.toString());
      writeSize(buffer, bytes.length);
      buffer.putUint8List(bytes);
    } else {
      super.writeValue(buffer, value);
    }
  }
}
```

### 3. Platform Implementations

#### Android Implementation

**MixpanelFlutterPlugin.java**:
```java
public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    switch (call.method) {
        case "track":
            handleTrack(call, result);
            break;
        // ... other methods
    }
}

private void handleTrack(MethodCall call, Result result) {
    String eventName = call.argument("eventName");
    Map<String, Object> mapProperties = call.<HashMap<String, Object>>argument("properties");
    JSONObject properties = new JSONObject(mapProperties == null ? EMPTY_HASHMAP : mapProperties);
    properties = MixpanelFlutterHelper.getMergedProperties(properties, mixpanelProperties);
    mixpanel.track(eventName, properties);
    result.success(null);
}
```

**MixpanelMessageCodec.java**: Mirrors Dart codec for Date/URI handling

#### iOS Implementation

**SwiftMixpanelFlutterPlugin.swift**:
```swift
private func handleTrack(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [String: Any]()
    let event = arguments["eventName"] as! String
    let properties = arguments["properties"] as? [String: Any]
    let mpProperties = MixpanelTypeHandler.mixpanelProperties(properties: properties, mixpanelProperties: mixpanelProperties)
    instance?.track(event: event, properties: mpProperties)
    result(nil)
}
```

**Custom codec implementation**:
```swift
public class MixpanelReader : FlutterStandardReader {
    public override func readValue(ofType type: UInt8) -> Any? {
        switch type {
            case DATE_TIME:
                var value: Int64 = 0
                readBytes(&value, length: 8)
                return Date(timeIntervalSince1970: TimeInterval(value / 1000))
            case URI:
                let urlString = readUTF8()
                return URL(string: urlString)
            default:
                return super.readValue(ofType: type)
        }
    }
}
```

#### Web Implementation

**mixpanel_flutter_web.dart**:
```dart
void handleTrack(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String eventName = args['eventName'] as String;
    dynamic properties = args['properties'];
    Map<String, dynamic> props = {
      ..._mixpanelProperties,
      ...(properties ?? {})
    };
    track(eventName, safeJsify(props));
}
```

**Type conversion for web**:
```dart
JSAny? safeJsify(dynamic value) {
  if (value == null) {
    return null;
  } else if (value is Map) {
    return value.jsify();
  } else if (value is DateTime) {
    return value.jsify();
  } // ... other type conversions
}
```

## Event Flow: track() Method

### 1. Initialization Flow

```dart
// Dart layer
final mixpanel = await Mixpanel.init("YOUR_PROJECT_TOKEN",
    optOutTrackingDefault: false, 
    trackAutomaticEvents: true);

// Platform channel invocation
await _channel.invokeMethod<void>('initialize', {
  'token': token,
  'optOutTrackingDefault': optOutTrackingDefault,
  'trackAutomaticEvents': trackAutomaticEvents,
  'mixpanelProperties': _mixpanelProperties,  // {$lib_version: '2.4.4', mp_lib: 'flutter'}
  'superProperties': superProperties,
  'config': config
});
```

### 2. Track Event Flow

```
Dart Layer (mixpanel.track("Event Name", properties: {...}))
    ↓
Platform Channel (invokeMethod('track', {eventName, properties}))
    ↓
Native Platform Handler
    ├── Android: MixpanelFlutterPlugin.handleTrack()
    ├── iOS: SwiftMixpanelFlutterPlugin.handleTrack()
    └── Web: MixpanelFlutterPlugin.handleTrack()
    ↓
Property Processing
    ├── Merge with library properties ($lib_version, mp_lib)
    ├── Type conversion (Date, URI, etc.)
    └── Platform-specific formatting
    ↓
Native SDK Call
    ├── Android: mixpanel.track(eventName, JSONObject)
    ├── iOS: instance?.track(event:properties:)
    └── Web: track(eventName, jsProperties)
    ↓
Mixpanel Servers
```

### 3. Data Serialization Details

#### Native Platforms (Android/iOS)
- Custom codec handles DateTime and Uri objects
- DateTime: Serialized as milliseconds since epoch (int64)
- Uri: Serialized as UTF-8 encoded string
- Complex objects (Maps, Lists) are recursively converted

#### Web Platform
- No custom codec needed - uses StandardMethodCodec
- `safeJsify()` converts Dart types to JavaScript-compatible types
- DateTime objects converted using `.jsify()`
- Direct JS interop with Mixpanel JavaScript library

## Key Design Decisions

1. **Platform Channel Architecture**: Enables code reuse while allowing platform-specific optimizations

2. **Custom Message Codec**: Ensures DateTime and Uri objects are properly serialized across platform boundaries

3. **Library Properties**: Automatically injected metadata (`$lib_version`, `mp_lib`) helps with analytics segmentation

4. **Async API**: All methods return Futures for consistency, even if underlying native calls are synchronous

5. **Type Safety**: Platform-specific type handlers ensure proper conversion between Dart and native types

6. **Web Implementation**: Uses JS interop instead of platform channels for better performance and smaller bundle size

## Platform Dependencies

- **Android**: Mixpanel Android SDK v8.0.3
- **iOS**: Mixpanel-swift v5.0.0  
- **Web**: Mixpanel JavaScript library (loaded from CDN)

## Example Usage

```dart
// Initialize
final mixpanel = await Mixpanel.init("YOUR_PROJECT_TOKEN",
    trackAutomaticEvents: true);

// Track simple event
await mixpanel.track("Button Clicked");

// Track with properties
await mixpanel.track("Purchase", properties: {
  "product": "Premium Subscription",
  "price": 9.99,
  "currency": "USD",
  "timestamp": DateTime.now(),
  "store_url": Uri.parse("https://store.example.com")
});

// Identify user
await mixpanel.identify("user123");

// Set user profile properties
mixpanel.getPeople().set("name", "John Doe");
mixpanel.getPeople().set("email", "john@example.com");

// Group analytics
mixpanel.setGroup("company", "Acme Corp");
final group = mixpanel.getGroup("company", "Acme Corp");
group.set("plan", "Enterprise");
```

## Architecture Benefits

1. **Unified API**: Developers write once, run everywhere
2. **Type Safety**: Strong typing prevents runtime errors
3. **Performance**: Native SDK usage ensures optimal performance per platform
4. **Maintainability**: Clear separation of concerns between layers
5. **Extensibility**: Easy to add new methods or platforms

## Future Considerations

1. **Null Safety**: The SDK fully supports Dart null safety
2. **Platform Expansion**: Architecture supports adding new platforms (e.g., Windows, Linux)
3. **Feature Parity**: Platform implementations should maintain feature parity where possible
4. **Testing**: Platform-specific functionality should be tested through the example app
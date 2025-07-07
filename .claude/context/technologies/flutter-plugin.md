# Flutter Plugin Development

## Overview
This SDK implements Flutter's federated plugin architecture, providing platform-specific implementations while maintaining a unified Dart API.

## Plugin Structure

### Federated Plugin Architecture
```yaml
# pubspec.yaml
flutter:
  plugin:
    platforms:
      android:
        package: com.mixpanel.mixpanel_flutter
        pluginClass: MixpanelFlutterPlugin
      ios:
        pluginClass: MixpanelFlutterPlugin
      web:
        pluginClass: MixpanelFlutterWeb
        fileName: mixpanel_flutter_web.dart
```

### Platform Interface Pattern
The SDK doesn't use the newer platform interface pattern, instead using direct platform channel communication:
```dart
static final MethodChannel _channel = kIsWeb
    ? const MethodChannel('mixpanel_flutter')
    : const MethodChannel(
        'mixpanel_flutter', StandardMethodCodec(MixpanelMessageCodec()));
```

## Platform Channel Communication

### Method Channel Usage
All communication uses named methods with argument maps:
```dart
// Dart side
await _channel.invokeMethod<void>('track', <String, dynamic>{
  'eventName': eventName,
  'properties': properties ?? {},
});

// Android side
@Override
public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    switch (call.method) {
        case "track":
            eventName = call.argument("eventName");
            properties = call.argument("properties");
            // Handle tracking
            break;
    }
}
```

### Custom Message Codec
Extends StandardMessageCodec to handle additional types:
```dart
class MixpanelMessageCodec extends StandardMessageCodec {
  static const int _typeDateTime = 128;
  static const int _typeUri = 129;
  
  @override
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
}
```

## Platform Detection

### Runtime Platform Checks
```dart
// Check for web platform
import 'package:flutter/foundation.dart' show kIsWeb;

// Usage
if (kIsWeb) {
  // Web-specific code
} else {
  // Mobile-specific code
}
```

### Conditional Imports
Web implementation loaded conditionally:
```dart
// In pubspec.yaml
dependencies:
  flutter_web_plugins:
    sdk: flutter
```

## Testing Strategy

### Mock Platform Channels
Tests use TestDefaultBinaryMessengerBinding:
```dart
TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
    .setMockMethodCallHandler(methodChannel, (MethodCall methodCall) async {
  lastMethodCall = methodCall;
  return null;
});
```

### Custom Matcher for Method Calls
```dart
class _IsMethodCall extends Matcher {
  final String method;
  final dynamic arguments;

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is! MethodCall) return false;
    if (item.method != method) return false;
    return arguments == null || item.arguments == arguments;
  }
}
```

## Best Practices Observed

### 1. **Consistent Method Naming**
Platform channel method names exactly match between Dart and native code.

### 2. **Argument Validation**
Input validation happens in Dart before platform calls:
```dart
if (_MixpanelHelper.isValidString(eventName)) {
  // Make platform call
} else {
  developer.log('`track` failed: eventName cannot be blank');
}
```

### 3. **Future Returns**
All methods return `Future<void>` for consistency:
```dart
Future<void> track(String eventName, {Map<String, dynamic>? properties}) async
```

### 4. **Null Safety**
Proper null handling with clear patterns:
```dart
properties: properties ?? {},
```

## Platform-Specific Considerations

### Android
- Plugin registered automatically via embedding v2
- Lazy initialization to prevent ANR
- JSON conversion for properties

### iOS
- Swift implementation with Objective-C compatibility
- Direct dictionary usage
- MixpanelType conversion for special types

### Web
- Pure Dart implementation
- JavaScript interop for native library
- Dynamic script loading
# Platform Channels

## Overview
Platform channels enable communication between Dart code and platform-specific implementations. This SDK uses MethodChannel with a custom message codec for type serialization.

## Channel Configuration

### Channel Setup
```dart
// From lib/mixpanel_flutter.dart
static final MethodChannel _channel = kIsWeb
    ? const MethodChannel('mixpanel_flutter')
    : const MethodChannel(
        'mixpanel_flutter', StandardMethodCodec(MixpanelMessageCodec()));
```

### Channel Name
Consistent channel name across all platforms: `'mixpanel_flutter'`

## Method Invocation Pattern

### Dart Side
All method calls follow this pattern:
```dart
Future<void> methodName(parameters) async {
  // 1. Validate inputs
  if (_MixpanelHelper.isValidString(parameter)) {
    // 2. Invoke platform method
    await _channel.invokeMethod<void>('methodName', <String, dynamic>{
      'param1': value1,
      'param2': value2,
    });
  } else {
    // 3. Log validation failures
    developer.log('`methodName` failed: reason', name: 'Mixpanel');
  }
}
```

### Argument Structure
Arguments always passed as Map<String, dynamic>:
```dart
// Simple method
await _channel.invokeMethod<void>('setLoggingEnabled', <String, dynamic>{
  'loggingEnabled': loggingEnabled,
});

// Complex method with nested data
await _channel.invokeMethod<void>('initialize', <String, dynamic>{
  'token': token,
  'optOutTrackingDefault': optOutTrackingDefault,
  'trackAutomaticEvents': trackAutomaticEvents,
  'superProperties': superProperties ?? {},
  'properties': mixpanelProperties,
  'config': config ?? {},
});
```

## Platform Implementations

### Android Handler
```java
public class MixpanelFlutterPlugin implements FlutterPlugin, MethodCallHandler {
  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    try {
      // Extract method name
      switch (call.method) {
        case "track":
          // Extract arguments
          String eventName = call.argument("eventName");
          Map<String, Object> properties = call.argument("properties");
          
          // Convert to platform types
          JSONObject jsonObject = MixpanelFlutterHelper.toJSONObject(properties);
          
          // Call native SDK
          mixpanel.track(eventName, jsonObject);
          
          // Return success
          result.success(null);
          break;
          
        default:
          result.notImplemented();
      }
    } catch (Exception e) {
      result.error("MixpanelFlutterException", e.getLocalizedMessage(), null);
    }
  }
}
```

### iOS Handler
```swift
public class SwiftMixpanelFlutterPlugin: NSObject, FlutterPlugin {
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "track":
      guard let arguments = call.arguments as? [String: Any],
            let eventName = arguments["eventName"] as? String else {
        result(nil)
        return
      }
      
      if let properties = arguments["properties"] as? [String: Any] {
        let mpProperties = convertToMixpanelTypes(properties)
        Mixpanel.mainInstance().track(event: eventName, properties: mpProperties)
      }
      
      result(nil)
      
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
```

## Custom Message Codec

### Purpose
Handles types not supported by StandardMessageCodec:
- DateTime objects
- Uri objects

### Implementation
```dart
class MixpanelMessageCodec extends StandardMessageCodec {
  const MixpanelMessageCodec();

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

  @override
  dynamic readValueOfType(int type, ReadBuffer buffer) {
    switch (type) {
      case _typeDateTime:
        return DateTime.fromMillisecondsSinceEpoch(buffer.getInt64());
      case _typeUri:
        final String uriString = readValueOfType(buffer.getUint8(), buffer);
        return Uri.parse(uriString);
      default:
        return super.readValueOfType(type, buffer);
    }
  }
}
```

### Platform Counterparts

#### Android (Java)
```java
public class MixpanelMessageCodec extends StandardMessageCodec {
  private static final byte DATE_TIME = (byte) 128;
  private static final byte URI = (byte) 129;

  @Override
  protected void writeValue(ByteArrayOutputStream stream, Object value) {
    if (value instanceof Date) {
      stream.write(DATE_TIME);
      writeLong(stream, ((Date) value).getTime());
    } else if (value instanceof Uri || value instanceof URI) {
      stream.write(URI);
      writeValue(stream, value.toString());
    } else {
      super.writeValue(stream, value);
    }
  }
}
```

#### iOS (Swift)
```swift
func convertToMixpanelTypes(_ properties: [String: Any]) -> Properties {
  var mixpanelProperties = Properties()
  for (key, value) in properties {
    if let date = value as? Date {
      mixpanelProperties[key] = date
    } else if let url = value as? URL {
      mixpanelProperties[key] = url
    } else {
      mixpanelProperties[key] = MixpanelType(value)
    }
  }
  return mixpanelProperties
}
```

## Error Handling

### Result Callbacks
Three types of results:
```dart
// Success
result.success(returnValue);

// Error
result.error("ErrorCode", "Error message", errorDetails);

// Not implemented
result.notImplemented();
```

### Error Propagation
Platform errors surface to Dart as PlatformException:
```dart
try {
  await _channel.invokeMethod('someMethod');
} on PlatformException catch (e) {
  // Handle platform-specific error
  print('Failed: ${e.message}');
}
```

## Best Practices

### 1. **Consistent Naming**
Method names must match exactly across platforms.

### 2. **Type Safety**
Always validate types on platform side:
```swift
guard let eventName = arguments["eventName"] as? String else {
  result(nil)
  return
}
```

### 3. **Null Handling**
Handle null/missing arguments gracefully:
```java
Map<String, Object> properties = call.argument("properties");
if (properties == null) {
  properties = new HashMap<>();
}
```

### 4. **Return Values**
Most tracking methods return void:
```dart
await _channel.invokeMethod<void>('track', args);
```

Methods that return values specify type:
```dart
final String? distinctId = await _channel.invokeMethod<String>('getDistinctId');
```
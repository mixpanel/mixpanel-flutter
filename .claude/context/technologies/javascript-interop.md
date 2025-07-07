# JavaScript Interop (Web Platform)

## Overview
The web implementation uses Dart's JavaScript interop capabilities to interface with the Mixpanel JavaScript library. This provides web support without needing platform channels.

## Library Loading

### HTML Setup Requirement
Users must add Mixpanel script to their HTML:
```html
<script type="text/javascript">
  (function(f,b){if(!b.__SV){var e,g,i,h;window.mixpanel=b;b._i=[];b.init=function(e,f,c){...}
  ...
  })(document,window.mixpanel||[]);
</script>
```

### Runtime Detection
The SDK checks for library presence:
```dart
// In mixpanel_flutter_web.dart
external MixpanelJs get mixpanelJs;

// Usage with null checks
if (mixpanelJs != null) {
  mixpanelJs.track(eventName, properties);
}
```

## JavaScript Bindings

### External Declarations
Using dart:js_interop for bindings:
```dart
// From lib/web/mixpanel_js_bindings.dart
@JS('mixpanel')
external MixpanelJs get mixpanelJs;

@JS()
@anonymous
abstract class MixpanelJs {
  external void init(String token, [dynamic config, String? name]);
  external void track(String eventName, [dynamic properties]);
  external void identify(String distinctId);
  external void alias(String alias, [String? original]);
  external void set_config(dynamic config);
  external People get people;
  external void register(dynamic properties);
  external void register_once(dynamic properties);
  // ... more methods
}
```

### People API Bindings
```dart
@JS()
@anonymous
abstract class People {
  external void set(dynamic properties);
  external void set_once(dynamic properties);
  external void unset(dynamic properties);
  external void increment(dynamic properties);
  external void append(dynamic properties);
  external void union(dynamic properties);
  external void remove(dynamic properties);
  external void delete_user();
  external void clear_charges();
}
```

## Type Conversion

### Safe JavaScript Conversion
The SDK provides a helper for safe type conversion:
```dart
dynamic safeJsify(Object value) {
  if (value is Map<dynamic, dynamic>) {
    // Convert to JS-compatible map
    value = JsLinkedHashMap.from(value);
  }
  var args = jsify(value);
  return args;
}
```

### Property Conversion Pattern
All property maps are converted before JS calls:
```dart
@override
Future<void> track(String eventName, Map<String, dynamic> properties) async {
  var trackedProperties = safeJsify(properties);
  mixpanelJs.track(eventName, trackedProperties);
}
```

## Web-Specific Implementation

### Platform Registration
```dart
class MixpanelFlutterWeb {
  static void registerWith(Registrar registrar) {
    final MethodChannel channel = MethodChannel(
      'mixpanel_flutter',
      const StandardMethodCodec(),
      registrar,
    );

    final pluginInstance = MixpanelFlutterWeb();
    channel.setMethodCallHandler(pluginInstance.handleMethodCall);
  }
}
```

### Method Handler
```dart
Future<dynamic> handleMethodCall(MethodCall call) async {
  switch (call.method) {
    case 'initialize':
      return initialize(
        call.arguments['token'],
        call.arguments['trackAutomaticEvents'],
        // ... other args
      );
    case 'track':
      return track(
        call.arguments['eventName'],
        call.arguments['properties'],
      );
    // ... other methods
  }
}
```

## Initialization Flow

### Web-Specific Init
```dart
@override
Future<void> initialize(
  String token,
  bool trackAutomaticEvents,
  Map<String, dynamic> superProperties,
  Map<String, dynamic> config,
) async {
  var webConfig = {
    'track_pageview': trackAutomaticEvents,
    ...config,
  };
  
  mixpanelJs.init(token, safeJsify(webConfig));
  
  if (superProperties.isNotEmpty) {
    mixpanelJs.register(safeJsify(superProperties));
  }
}
```

## DateTime Handling

### Web Platform Difference
Unlike mobile platforms that use custom codec, web handles DateTime differently:
```dart
// Web converts DateTime to ISO string in properties
if (value is DateTime) {
  return value.toIso8601String();
}
```

## Group Analytics

### Group API Bindings
```dart
@JS()
@anonymous
abstract class Group {
  external void set(dynamic properties);
  external void set_once(dynamic properties);
  external void unset(dynamic properties);
  external void union(dynamic properties);
  external void remove(dynamic properties);
  external void delete_group();
}
```

### Group Access Pattern
```dart
@override
Future<void> groupSetProperties(
  String groupKey,
  dynamic groupID,
  Map<String, dynamic> properties,
) async {
  var group = mixpanelJs.get_group(groupKey, groupID);
  group.set(safeJsify(properties));
}
```

## Error Handling

### Null Check Pattern
Web implementation uses null checks instead of try-catch:
```dart
if (mixpanelJs != null) {
  mixpanelJs.track(eventName, properties);
} else {
  print('Mixpanel JS library not loaded');
}
```

## Best Practices

### 1. **Type Safety**
Always use safeJsify for complex objects:
```dart
var jsProperties = safeJsify(properties);
```

### 2. **Library Detection**
Check for library presence before operations:
```dart
external MixpanelJs? get mixpanelJs;
```

### 3. **Consistent API**
Web implementation mirrors mobile API exactly:
```dart
// Same method signature as mobile
Future<void> track(String eventName, {Map<String, dynamic>? properties})
```

### 4. **Configuration Mapping**
Map Flutter config to JS equivalents:
```dart
var webConfig = {
  'track_pageview': trackAutomaticEvents,
  'persistence': 'localStorage',
  // Map other Flutter configs
};
```

## Limitations

### No Custom Codec
Web uses standard JSON serialization, so:
- DateTime converted to ISO strings
- Uri converted to strings
- No binary data support

### Script Loading
Requires manual script inclusion in HTML, cannot be loaded dynamically by the SDK.
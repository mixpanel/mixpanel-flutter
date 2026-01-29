import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:mixpanel_flutter/web/mixpanel_js_bindings.dart';

/// Safely converts Dart values to JavaScript-compatible types for web interop.
///
/// This function handles the conversion of various Dart types to their JavaScript
/// equivalents using the appropriate JS interop methods.
///
/// **Accepted input types:**
/// - `JSAny` - Returned as-is to avoid double conversion
/// - `Map` - Converted using `.jsify()` to a JavaScript object
/// - `List` - Converted using `.jsify()` to a JavaScript array
/// - `DateTime` - Converted using `.jsify()` to a JavaScript Date object
/// - `bool` - Converted using `.toJS` to a JavaScript boolean
/// - `num` (int/double) - Converted using `.toJS` to a JavaScript number
/// - `String` - Converted using `.toJS` to a JavaScript string
/// - Any other type - Logs a warning and returns null to prevent JS interop issues
///
/// **Return value:**
/// Returns a `JSAny?` which represents the JavaScript-compatible value.
/// The return type is nullable to handle cases where the input cannot be
/// converted or is already null.
///
/// **Null handling:**
/// - If the input value is `null`, it is explicitly checked and returned immediately
/// - The function is null-safe and will not throw on null inputs
///
/// **Example usage:**
/// ```dart
/// Convert a Map to JavaScript object
/// var jsObj = safeJsify({'key': 'value', 'count': 42});
///
/// Convert a List to JavaScript array
/// var jsArray = safeJsify([1, 2, 3, 'four']);
///
/// Handles null gracefully
/// var jsNull = safeJsify(null); // Returns null
/// ```
JSAny? safeJsify(dynamic value) {
  if (value == null) {
    return null;
  } else if (value is Map) {
    return value.jsify();
  } else if (value is List) {
    return value.jsify();
  } else if (value is DateTime) {
    return value.jsify();
  } else if (value is bool) {
    return value.toJS;
  } else if (value is num) {
    return value.toJS;
  } else if (value is String) {
    return value.toJS;
  } else {
    debugPrint(
        '[Mixpanel] Warning: Unsupported type for JS conversion: ${value.runtimeType}. '
        'Value will be ignored. Supported types are: Map, List, DateTime, bool, num, String, JSAny, and null.');
    return null;
  }
}

/// A web implementation of the MixpanelFlutter plugin.
class MixpanelFlutterPlugin {
  static final Map<String, String> _mixpanelProperties = {
    '\$lib_version': '1.3.1',
    'mp_lib': 'flutter',
  };

  static void registerWith(Registrar registrar) {
    // Web platform doesn't need the custom codec since safeJsify handles type conversions
    final MethodChannel channel = MethodChannel(
      'mixpanel_flutter',
      const StandardMethodCodec(),
      registrar,
    );

    final pluginInstance = MixpanelFlutterPlugin();
    channel.setMethodCallHandler(pluginInstance.handleMethodCall);
  }

  /// Handles method calls over the MethodChannel of this plugin.
  /// Note: Check the "federated" architecture for a new way of doing this:
  /// https://flutter.dev/go/federated-plugins
  Future<dynamic> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'initialize':
        initialize(call);
        break;
      case 'setServerURL':
        handleSetServerURL(call);
        break;
      case "hasOptedOutTracking":
        return handleHasOptedOutTracking();
      case "optInTracking":
        handleOptInTracking();
        break;
      case "optOutTracking":
        handleOptOutTracking();
        break;
      case "setLoggingEnabled":
        handleSetLoggingEnabled(call);
        break;
      case "identify":
        handleIdentify(call);
        break;
      case "alias":
        handleAlias(call);
        break;
      case 'track':
        handleTrack(call);
        break;
      case "trackWithGroups":
        handleTrackWithGroups(call);
        break;
      case "setGroup":
        handleSetGroup(call);
        break;
      case "addGroup":
        handleAddGroup(call);
        break;
      case "removeGroup":
        handleRemoveGroup(call);
        break;
      case "registerSuperProperties":
        handleRegisterSuperProperties(call);
        break;
      case "registerSuperPropertiesOnce":
        handleRegisterSuperPropertiesOnce(call);
        break;
      case "unregisterSuperProperty":
        handleUnregisterSuperProperty(call);
        break;
      case "timeEvent":
        handleTimeEvent(call);
        break;
      case "reset":
        handleReset();
        break;
      case "getDistinctId":
        return handleGetDistinctId();
      case "set":
        handleSet(call);
        break;
      case "setOnce":
        handleSetOnce(call);
        break;
      case "increment":
        handlePeopleIncrement(call);
        break;
      case "append":
        handlePeopleAppend(call);
        break;
      case "union":
        handlePeopleUnion(call);
        break;
      case "remove":
        handlePeopleRemove(call);
        break;
      case "unset":
        handlePeopleUnset(call);
        break;
      case "trackCharge":
        handleTrackCharge(call);
        break;
      case "clearCharge":
        handleClearCharge();
        break;
      case "deleteUsers":
        handleDeleteUsers();
        break;
      case "groupSetProperties":
        handleGroupSetProperties(call);
        break;
      case "groupSetPropertyOnce":
        handleGroupSetPropertyOnce(call);
        break;
      case "groupUnsetProperty":
        handleGroupUnsetProperty(call);
        break;
      case "groupRemovePropertyValue":
        handleGroupRemove(call);
        break;
      case "groupUnionProperty":
        handleGroupUnion(call);
        break;
      case "areFlagsReady":
        return handleAreFlagsReady();
      case "getVariant":
        return handleGetVariant(call);
      case "getVariantSync":
        return handleGetVariantSync(call);
      case "getVariantValue":
        return handleGetVariantValue(call);
      case "getVariantValueSync":
        return handleGetVariantValueSync(call);
      case "isEnabled":
        return handleIsEnabled(call);
      case "isEnabledSync":
        return handleIsEnabledSync(call);
      case "updateFlagsContext":
        handleUpdateFlagsContext(call);
        break;
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details:
              'mixpanel_flutter for web doesn\'t implement \'${call.method}\'',
        );
    }
  }

  void initialize(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String token = args['token'] as String;
    dynamic config = args['config'];
    Map<String, dynamic> initConfig = Map<String, dynamic>.from(config ?? {});

    // Handle feature flags configuration
    dynamic featureFlags = args['featureFlags'];
    if (featureFlags != null && featureFlags is Map) {
      bool enabled = featureFlags['enabled'] == true;
      if (enabled) {
        dynamic context = featureFlags['context'];
        if (context != null && context is Map && context.isNotEmpty) {
          initConfig['flags'] = {'context': context};
        } else {
          initConfig['flags'] = true;
        }
      }
    }

    init(token, safeJsify(initConfig));
  }

  void handleSetServerURL(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String serverURL = args['serverURL'] as String;
    set_config(safeJsify({'api_host': serverURL}));
  }

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

  void handleAlias(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String aliasName = args['alias'] as String;
    String distinctId = args['distinctId'] as String;
    alias(aliasName, distinctId);
  }

  void handleIdentify(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String distinctId = args['distinctId'] as String;
    identify(distinctId);
  }

  void handleTrackWithGroups(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String eventName = args['eventName'] as String;
    dynamic properties = args['properties'];
    Map<String, dynamic> props = {
      ..._mixpanelProperties,
      ...(properties ?? {})
    };
    dynamic groups = args["groups"];
    track_with_groups(eventName, safeJsify(props), safeJsify(groups));
  }

  void handleSetGroup(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String groupKey = args['groupKey'] as String;
    dynamic groupID = args["groupID"];
    if (groupID != null) {
      set_group(groupKey, safeJsify(groupID));
    }
  }

  void handleAddGroup(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String groupKey = args['groupKey'] as String;
    dynamic groupID = args["groupID"];

    if (groupID != null) {
      add_group(groupKey, safeJsify(groupID));
    }
  }

  void handleRemoveGroup(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String groupKey = args['groupKey'] as String;
    dynamic groupID = args["groupID"];
    if (groupID != null) {
      remove_group(groupKey, safeJsify(groupID));
    }
  }

  void handleRegisterSuperProperties(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    dynamic properties = args['properties'];
    register(safeJsify(properties));
  }

  void handleRegisterSuperPropertiesOnce(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    dynamic properties = args['properties'];
    register_once(safeJsify(properties));
  }

  void handleUnregisterSuperProperty(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String propertyName = args['propertyName'] as String;
    unregister(propertyName);
  }

  void handleTimeEvent(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String eventName = args['eventName'] as String;
    time_event(eventName);
  }

  void handleReset() {
    reset();
  }

  String handleGetDistinctId() {
    return get_distinct_id();
  }

  void handleSet(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    dynamic properties = args['properties'];
    Map<String, dynamic> props = {..._mixpanelProperties, ...properties};
    people_set(safeJsify(props));
  }

  void handleSetOnce(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    dynamic properties = args['properties'];
    Map<String, dynamic> props = {..._mixpanelProperties, ...properties};
    people_set_once(safeJsify(props));
  }

  void handlePeopleIncrement(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    dynamic properties = args['properties'];
    people_increment(safeJsify(properties));
  }

  void handlePeopleAppend(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    dynamic properties = args['properties'];
    people_append(safeJsify(properties));
  }

  void handlePeopleUnion(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    dynamic properties = args['properties'];
    people_union(safeJsify(properties));
  }

  void handlePeopleRemove(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    dynamic properties = args['properties'];
    people_remove(safeJsify(properties));
  }

  void handlePeopleUnset(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    dynamic properties = args['properties'];
    people_unset(safeJsify(properties));
  }

  void handleTrackCharge(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    dynamic properties = args['properties'];
    double amount = args['amount'] as double;
    people_track_charge(amount, safeJsify(properties ?? <String, dynamic>{}));
  }

  void handleClearCharge() {
    people_clear_charge();
  }

  void handleDeleteUsers() {
    people_delete_users();
  }

  void handleGroupSetProperties(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String groupKey = args['groupKey'] as String;
    dynamic groupID = args['groupID'];

    dynamic properties = args['properties'];
    get_group(groupKey, safeJsify(groupID)).set(safeJsify(properties));
  }

  void handleGroupSetPropertyOnce(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String groupKey = args['groupKey'] as String;
    dynamic groupID = args['groupID'];

    dynamic properties = args['properties'];

    get_group(groupKey, safeJsify(groupID))
        .set_once(properties.keys.first, properties[properties.keys.first]);
  }

  void handleGroupUnsetProperty(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String groupKey = args['groupKey'] as String;
    dynamic groupID = args['groupID'];

    String propertyName = args['propertyName'] as String;
    get_group(groupKey, safeJsify(groupID)).unset(propertyName);
  }

  void handleGroupRemove(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String groupKey = args['groupKey'] as String;
    dynamic groupID = args['groupID'];

    String name = args['name'] as String;
    dynamic value = args['value'];
    get_group(groupKey, safeJsify(groupID)).remove(name, safeJsify(value));
  }

  void handleGroupUnion(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String groupKey = args['groupKey'] as String;
    dynamic groupID = args['groupID'];

    String name = args['name'] as String;
    JSAny? value = safeJsify(args['value'] as dynamic);
    get_group(groupKey, safeJsify(groupID))
        .union(name, value is JSArray ? value : <JSAny>[].toJS);
  }

  bool handleHasOptedOutTracking() {
    return has_opted_out_tracking();
  }

  void handleOptInTracking() {
    opt_in_tracking();
  }

  void handleOptOutTracking() {
    opt_out_tracking();
  }

  void handleSetLoggingEnabled(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    bool loggingEnabled = args['loggingEnabled'] as bool;
    set_config(safeJsify({'debug': loggingEnabled}));
  }

  // Feature Flags handlers

  bool handleAreFlagsReady() {
    return flags_are_flags_ready();
  }

  Future<Map<String, dynamic>> handleGetVariant(MethodCall call) async {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String flagName = args['flagName'] as String;
    Map<Object?, Object?> fallbackMap = args['fallback'] as Map<Object?, Object?>? ?? {};

    JSAny? fallbackJs = safeJsify({
      'key': fallbackMap['key'],
      'value': fallbackMap['value'],
    });

    try {
      JSPromise promise = flags_get_variant(flagName, fallbackJs);
      JSAny? jsResult = await promise.toDart;
      return _jsVariantToMap(jsResult, fallbackMap);
    } catch (e) {
      debugPrint('[Mixpanel] getVariant failed with error: $e, returning fallback');
      return _jsVariantToMap(null, fallbackMap);
    }
  }

  Map<String, dynamic> handleGetVariantSync(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String flagName = args['flagName'] as String;
    Map<Object?, Object?> fallbackMap = args['fallback'] as Map<Object?, Object?>? ?? {};

    JSAny? fallbackJs = safeJsify({
      'key': fallbackMap['key'],
      'value': fallbackMap['value'],
    });

    try {
      JSAny? jsResult = flags_get_variant_sync(flagName, fallbackJs);
      return _jsVariantToMap(jsResult, fallbackMap);
    } catch (e) {
      debugPrint('[Mixpanel] getVariantSync failed with error: $e, returning fallback');
      return _jsVariantToMap(null, fallbackMap);
    }
  }

  Future<dynamic> handleGetVariantValue(MethodCall call) async {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String flagName = args['flagName'] as String;
    dynamic fallbackValue = args['fallbackValue'];

    JSAny? fallbackJs = safeJsify({
      'key': flagName,
      'value': fallbackValue,
    });

    try {
      JSPromise promise = flags_get_variant(flagName, fallbackJs);
      JSAny? jsResult = await promise.toDart;
      Map<String, dynamic> variant = _jsVariantToMap(jsResult, {'key': flagName, 'value': fallbackValue});
      return variant['value'] ?? fallbackValue;
    } catch (e) {
      debugPrint('[Mixpanel] getVariantValue failed with error: $e, returning fallback');
      return fallbackValue;
    }
  }

  dynamic handleGetVariantValueSync(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String flagName = args['flagName'] as String;
    dynamic fallbackValue = args['fallbackValue'];

    JSAny? fallbackJs = safeJsify({
      'key': flagName,
      'value': fallbackValue,
    });

    try {
      JSAny? jsResult = flags_get_variant_sync(flagName, fallbackJs);
      Map<String, dynamic> variant = _jsVariantToMap(jsResult, {'key': flagName, 'value': fallbackValue});
      return variant['value'] ?? fallbackValue;
    } catch (e) {
      debugPrint('[Mixpanel] getVariantValueSync failed with error: $e, returning fallback');
      return fallbackValue;
    }
  }

  Future<bool> handleIsEnabled(MethodCall call) async {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String flagName = args['flagName'] as String;
    bool fallbackValue = args['fallbackValue'] as bool? ?? false;

    JSAny? fallbackJs = safeJsify({
      'key': flagName,
      'value': fallbackValue,
    });

    try {
      JSPromise promise = flags_get_variant(flagName, fallbackJs);
      JSAny? jsResult = await promise.toDart;
      Map<String, dynamic> variant = _jsVariantToMap(jsResult, {'key': flagName, 'value': fallbackValue});
      dynamic value = variant['value'];
      if (value is bool) {
        return value;
      }
      if (value != null) {
        debugPrint('[Mixpanel] isEnabled flag \'$flagName\' has non-boolean value, returning fallback');
      }
      return fallbackValue;
    } catch (e) {
      debugPrint('[Mixpanel] isEnabled failed with error: $e, returning fallback');
      return fallbackValue;
    }
  }

  bool handleIsEnabledSync(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String flagName = args['flagName'] as String;
    bool fallbackValue = args['fallbackValue'] as bool? ?? false;

    JSAny? fallbackJs = safeJsify({
      'key': flagName,
      'value': fallbackValue,
    });

    try {
      JSAny? jsResult = flags_get_variant_sync(flagName, fallbackJs);
      Map<String, dynamic> variant = _jsVariantToMap(jsResult, {'key': flagName, 'value': fallbackValue});
      dynamic value = variant['value'];
      if (value is bool) {
        return value;
      }
      if (value != null) {
        debugPrint('[Mixpanel] isEnabledSync flag \'$flagName\' has non-boolean value, returning fallback');
      }
      return fallbackValue;
    } catch (e) {
      debugPrint('[Mixpanel] isEnabledSync failed with error: $e, returning fallback');
      return fallbackValue;
    }
  }

  void handleUpdateFlagsContext(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    dynamic context = args['context'];
    flags_update_context(safeJsify(context ?? {}));
  }

  Map<String, dynamic> _jsVariantToMap(JSAny? jsResult, Map<Object?, Object?> fallbackMap) {
    if (jsResult == null) {
      debugPrint('[Mixpanel] _jsVariantToMap received null result, returning fallback');
      return {
        'key': fallbackMap['key'] as String? ?? '',
        'value': fallbackMap['value'],
        'experimentId': null,
        'isExperimentActive': null,
        'isQaTester': null,
      };
    }

    // Convert JS object to Dart map
    try {
      Map<Object?, Object?>? dartMap = (jsResult as JSObject).dartify() as Map<Object?, Object?>?;
      if (dartMap == null) {
        debugPrint('[Mixpanel] _jsVariantToMap failed to convert JS object, returning fallback');
        return {
          'key': fallbackMap['key'] as String? ?? '',
          'value': fallbackMap['value'],
          'experimentId': null,
          'isExperimentActive': null,
          'isQaTester': null,
        };
      }

      return {
        'key': dartMap['key'] as String? ?? '',
        'value': dartMap['value'],
        'experimentId': dartMap['experiment_id'] as String?,
        'isExperimentActive': dartMap['is_experiment_active'] as bool?,
        'isQaTester': dartMap['is_qa_tester'] as bool?,
      };
    } catch (e) {
      debugPrint('[Mixpanel] _jsVariantToMap failed with error: $e, returning fallback');
      return {
        'key': fallbackMap['key'] as String? ?? '',
        'value': fallbackMap['value'],
        'experimentId': null,
        'isExperimentActive': null,
        'isQaTester': null,
      };
    }
  }
}

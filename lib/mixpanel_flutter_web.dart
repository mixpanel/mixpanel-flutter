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
    } else if (value is JSAny) {
      return value;
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
      debugPrint('[Mixpanel] Warning: Unsupported type for JS conversion: ${value.runtimeType}. '
                 'Value will be ignored. Supported types are: Map, List, DateTime, bool, num, String, JSAny, and null.');
      return null;
    }
  }

/// A web implementation of the MixpanelFlutter plugin.
class MixpanelFlutterPlugin {
  static Map<String, String> _mixpanelProperties = {
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
    init(token, safeJsify(config ?? <String, dynamic>{}));
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
    get_group(groupKey, safeJsify(groupID))
        .set(safeJsify(properties));
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
    get_group(groupKey, safeJsify(groupID))
        .unset(propertyName);
  }

  void handleGroupRemove(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String groupKey = args['groupKey'] as String;
    dynamic groupID = args['groupID'];

    String name = args['name'] as String;
    dynamic value = args['value'];
    get_group(groupKey, safeJsify(groupID))
        .remove(name, safeJsify(value));
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
}

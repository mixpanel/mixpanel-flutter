import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:mixpanel_flutter/web/mixpanel_js_bindings.dart';

/// A web implementation of the MixpanelFlutter plugin.
class MixpanelFlutterPlugin {
  static Map<String, String> _mixpanelProperties = {
    '\$lib_version': '1.3.1',
    'mp_lib': 'flutter',
  };

  static void registerWith(Registrar registrar) {
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
    init(token, config?.jsify() ?? {});
  }

  void handleSetServerURL(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String serverURL = args['serverURL'] as String;
    set_config({'api_host': serverURL}.jsify());
  }

  void handleTrack(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String eventName = args['eventName'] as String;
    dynamic properties = args['properties'];
    Map<String, dynamic> props = {
      ..._mixpanelProperties,
      ...(properties ?? {})
    };
    track(eventName, props.jsify());
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
    track_with_groups(eventName, props.jsify(), groups.jsify());
  }

  void handleSetGroup(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String groupKey = args['groupKey'] as String;
    dynamic groupID = args["groupID"];
    if (groupID != null) {
      set_group(groupKey,
          (groupID is Map || groupID is List) ? groupID.jsify() : groupID);
    }
  }

  void handleAddGroup(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String groupKey = args['groupKey'] as String;
    dynamic groupID = args["groupID"];

    if (groupID != null) {
      add_group(groupKey,
          (groupID is Map || groupID is List) ? groupID.jsify() : groupID);
    }
  }

  void handleRemoveGroup(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String groupKey = args['groupKey'] as String;
    dynamic groupID = args["groupID"];
    if (groupID != null) {
      remove_group(groupKey,
          (groupID is Map || groupID is List) ? groupID.jsify() : groupID);
    }
  }

  void handleRegisterSuperProperties(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    dynamic properties = args['properties'];
    register(properties.jsify());
  }

  void handleRegisterSuperPropertiesOnce(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    dynamic properties = args['properties'];
    register_once(properties.jsify());
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
    people_set(props.jsify());
  }

  void handleSetOnce(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    dynamic properties = args['properties'];
    Map<String, dynamic> props = {..._mixpanelProperties, ...properties};
    people_set_once(props.jsify());
  }

  void handlePeopleIncrement(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    dynamic properties = args['properties'];
    people_increment(properties.jsify());
  }

  void handlePeopleAppend(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    dynamic properties = args['properties'];
    people_append(properties.jsify());
  }

  void handlePeopleUnion(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    dynamic properties = args['properties'];
    people_union(properties.jsify());
  }

  void handlePeopleRemove(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    dynamic properties = args['properties'];
    people_remove(properties.jsify());
  }

  void handlePeopleUnset(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    dynamic properties = args['properties'];
    people_unset(properties.jsify());
  }

  void handleTrackCharge(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    dynamic properties = args['properties'];
    double amount = args['amount'] as double;
    people_track_charge(amount, properties?.jsify() ?? {});
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
    get_group(groupKey,
            (groupID is Map || groupID is List) ? groupID.jsify() : groupID)
        .set(properties.jsify());
  }

  void handleGroupSetPropertyOnce(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String groupKey = args['groupKey'] as String;
    dynamic groupID = args['groupID'];

    dynamic properties = args['properties'];

    get_group(groupKey,
            (groupID is Map || groupID is List) ? groupID.jsify() : groupID)
        .set_once(properties.keys.first, properties[properties.keys.first]);
  }

  void handleGroupUnsetProperty(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String groupKey = args['groupKey'] as String;
    dynamic groupID = args['groupID'];

    String propertyName = args['propertyName'] as String;
    get_group(groupKey,
            (groupID is Map || groupID is List) ? groupID.jsify() : groupID)
        .unset(propertyName);
  }

  void handleGroupRemove(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String groupKey = args['groupKey'] as String;
    dynamic groupID = args['groupID'];

    String name = args['name'] as String;
    dynamic value = args['value'];
    get_group(groupKey,
            (groupID is Map || groupID is List) ? groupID.jsify() : groupID)
        .remove(
            name, (value is Map || value is List) ? value.jsify() : value);
  }

  void handleGroupUnion(MethodCall call) {
    Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    String groupKey = args['groupKey'] as String;
    dynamic groupID = args['groupID'];

    String name = args['name'] as String;
    dynamic value = args['value'] as dynamic;
    get_group(groupKey,
            (groupID is Map || groupID is List) ? groupID.jsify() : groupID)
        .union(name, value.jsify());
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

package com.mixpanel.mixpanel_flutter;

import androidx.annotation.NonNull;

import android.content.Context;

import io.flutter.plugin.common.StandardMethodCodec;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;

import com.mixpanel.android.mpmetrics.MixpanelAPI;

/**
 * MixpanelFlutterPlugin
 */
public class MixpanelFlutterPlugin implements FlutterPlugin, MethodCallHandler {

    private MethodChannel channel;
    private MixpanelAPI mixpanel;
    private Context context;
    private JSONObject mixpanelProperties;

    private static final Map<String, Object> EMPTY_HASHMAP = new HashMap<>();

    public MixpanelFlutterPlugin() {
    }

    public MixpanelFlutterPlugin(Context context) {
        this.context = context;
    }

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "mixpanel_flutter",
                new StandardMethodCodec(new MixpanelMessageCodec()));
        context = flutterPluginBinding.getApplicationContext();
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        switch (call.method) {
            case "initialize":
                handleInitialize(call, result);
                break;
            case "setServerURL":
                handleSetServerURL(call, result);
                break;
            case "setLoggingEnabled":
                handleSetLoggingEnabled(call, result);
                break;
            case "setUseIpAddressForGeolocation":
                handleSetUseIpAddressForGeolocation(call, result);
                break;
            case "hasOptedOutTracking":
                handleHasOptedOutTracking(call, result);
                break;
            case "optInTracking":
                handleOptInTracking(call, result);
                break;
            case "optOutTracking":
                handleOptOutTracking(call, result);
                break;
            case "setFlushBatchSize":
                handleSetFlushBatchSize(call, result);
            case "identify":
                handleIdentify(call, result);
                break;
            case "alias":
                handleAlias(call, result);
                break;
            case "track":
                handleTrack(call, result);
                break;
            case "trackWithGroups":
                handleTrackWithGroups(call, result);
                break;
            case "setGroup":
                handleSetGroup(call, result);
                break;
            case "addGroup":
                handleAddGroup(call, result);
                break;
            case "removeGroup":
                handleRemoveGroup(call, result);
                break;
            case "deleteGroup":
                handleDeleteGroup(call, result);
                break;
            case "registerSuperProperties":
                handleRegisterSuperProperties(call, result);
                break;
            case "registerSuperPropertiesOnce":
                handleRegisterSuperPropertiesOnce(call, result);
                break;
            case "unregisterSuperProperty":
                handleUnregisterSuperProperty(call, result);
                break;
            case "getSuperProperties":
                handleGetSuperProperties(call, result);
                break;
            case "clearSuperProperties":
                handleClearSuperProperties(call, result);
                break;
            case "timeEvent":
                handleTimeEvent(call, result);
                break;
            case "eventElapsedTime":
                handleEventElapsedTime(call, result);
                break;
            case "reset":
                handleReset(call, result);
                break;
            case "getDistinctId":
                handleGetDistinctId(call, result);
                break;
            case "flush":
                handleFlush(call, result);
                break;
            case "set":
                handleSet(call, result);
                break;
            case "setOnce":
                handleSetOnce(call, result);
                break;
            case "increment":
                handleIncrement(call, result);
                break;
            case "append":
                handleAppend(call, result);
                break;
            case "union":
                handleUnion(call, result);
                break;
            case "remove":
                handleRemove(call, result);
                break;
            case "unset":
                handleUnset(call, result);
                break;
            case "trackCharge":
                handleTrackCharge(call, result);
                break;
            case "clearCharges":
                handleClearCharges(call, result);
                break;
            case "deleteUser":
                handleDeleteUser(call, result);
                break;
            case "groupSetProperties":
                handleGroupSetProperties(call, result);
                break;
            case "groupSetPropertyOnce":
                handleGroupSetPropertyOnce(call, result);
                break;
            case "groupUnsetProperty":
                handleGroupUnsetProperty(call, result);
                break;
            case "groupRemovePropertyValue":
                handleGroupRemovePropertyValue(call, result);
                break;
            case "groupUnionProperty":
                handleGroupUnionProperty(call, result);
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    private void handleInitialize(MethodCall call, Result result) {
        final String token = call.argument("token");
        if (token == null) {
            throw new RuntimeException("Your Mixpanel Token was not set");
        }
        Map<String, Object> mixpanelPropertiesMap =
                call.<HashMap<String, Object>>argument("mixpanelProperties");
        mixpanelProperties =
                new JSONObject(mixpanelPropertiesMap == null ? EMPTY_HASHMAP : mixpanelPropertiesMap);
        Map<String, Object> superPropertiesMap =
                call.<HashMap<String, Object>>argument("superProperties");
        JSONObject superProperties =
                new JSONObject(superPropertiesMap == null ? EMPTY_HASHMAP : superPropertiesMap);
        JSONObject superAndMixpanelProperties;
        try {
            superAndMixpanelProperties =
                    MixpanelFlutterHelper.getMergedProperties(superProperties, mixpanelProperties);
        } catch (JSONException e) {
            result.error("MixpanelFlutterException", e.getLocalizedMessage(), null);
            return;
        }

        Boolean optOutTrackingDefault = call.<Boolean>argument("optOutTrackingDefault");
        Boolean trackAutomaticEvents = call.<Boolean>argument("trackAutomaticEvents");

        mixpanel = MixpanelAPI.getInstance(context, token,
                optOutTrackingDefault == null ? false : optOutTrackingDefault,
                superAndMixpanelProperties, null, trackAutomaticEvents);

        result.success(Integer.toString(mixpanel.hashCode()));
    }

    private void handleSetServerURL(MethodCall call, Result result) {
        String serverURL = call.argument("serverURL");
        mixpanel.setServerURL(serverURL);
        result.success(null);
    }

    private void handleSetLoggingEnabled(MethodCall call, Result result) {
        Boolean enableLogging = call.argument("loggingEnabled");
        mixpanel.setEnableLogging(enableLogging);
        result.success(null);
    }

    private void handleSetUseIpAddressForGeolocation(MethodCall call, Result result) {
        Boolean useIpAddressForGeolocation = call.argument("useIpAddressForGeolocation");
        mixpanel.setUseIpAddressForGeolocation(useIpAddressForGeolocation);
        result.success(null);
    }

    private void handleHasOptedOutTracking(MethodCall call, Result result) {
        result.success(mixpanel.hasOptedOutTracking());
    }

    private void handleOptInTracking(MethodCall call, Result result) {
        mixpanel.optInTracking(null, mixpanelProperties);
        result.success(null);
    }

    private void handleOptOutTracking(MethodCall call, Result result) {
        mixpanel.optOutTracking();
        result.success(null);
    }

    private void handleSetFlushBatchSize(MethodCall call, Result result) {
        int flushBatchSize = call.argument("flushBatchSize");
        mixpanel.setFlushBatchSize(flushBatchSize);
        result.success(null);
    }

    private void handleIdentify(MethodCall call, Result result) {
        String distinctId = call.argument("distinctId");
        mixpanel.identify(distinctId);
        result.success(null);
    }

    private void handleAlias(MethodCall call, Result result) {
        String distinctId = call.argument("distinctId");
        String alias = call.argument("alias");
        mixpanel.alias(alias, distinctId);
        result.success(null);
    }

    private void handleTrack(MethodCall call, Result result) {
        String eventName = call.argument("eventName");
        Map<String, Object> mapProperties = call.<HashMap<String, Object>>argument("properties");
        JSONObject properties;
        try {
            properties = new JSONObject(mapProperties == null ? EMPTY_HASHMAP : mapProperties);
            properties = MixpanelFlutterHelper.getMergedProperties(properties, mixpanelProperties);
        } catch (JSONException e) {
            result.error("MixpanelFlutterException", e.getLocalizedMessage(), null);
            return;
        }
        mixpanel.track(eventName, properties);
        result.success(null);
    }

    private void handleRegisterSuperProperties(MethodCall call, Result result) {
        Map<String, Object> mapProperties = call.<HashMap<String, Object>>argument("properties");
        JSONObject properties;
        try {
            properties = new JSONObject(mapProperties == null ? EMPTY_HASHMAP : mapProperties);
            properties = MixpanelFlutterHelper.getMergedProperties(properties, mixpanelProperties);
        } catch (JSONException e) {
            result.error("MixpanelFlutterException", e.getLocalizedMessage(), null);
            return;
        }
        mixpanel.registerSuperProperties(properties);
        result.success(null);
    }

    private void handleRegisterSuperPropertiesOnce(MethodCall call, Result result) {
        Map<String, Object> mapProperties = call.<HashMap<String, Object>>argument("properties");
        JSONObject properties;
        try {
            properties = new JSONObject(mapProperties == null ? EMPTY_HASHMAP : mapProperties);
            properties = MixpanelFlutterHelper.getMergedProperties(properties, mixpanelProperties);
        } catch (JSONException e) {
            result.error("MixpanelFlutterException", e.getLocalizedMessage(), null);
            return;
        }
        mixpanel.registerSuperPropertiesOnce(properties);
        result.success(null);
    }

    private void handleUnregisterSuperProperty(MethodCall call, Result result) {
        String propertyName = call.argument("propertyName");
        mixpanel.unregisterSuperProperty(propertyName);
        result.success(null);
    }

    private void handleUnion(MethodCall call, Result result) {
        String name = call.argument("name");
        ArrayList<Object> value = call.argument("value");
        mixpanel.getPeople().union(name, new JSONArray(value));
        result.success(null);
    }

    private void handleGetSuperProperties(MethodCall call, Result result) {
        try {
            result.success(MixpanelFlutterHelper.toMap(mixpanel.getSuperProperties()));
        } catch (JSONException e) {
            result.error("MixpanelFlutterException", e.getLocalizedMessage(), null);
            result.success(null);
        }
    }

    private void handleClearSuperProperties(MethodCall call, Result result) {
        mixpanel.clearSuperProperties();
        result.success(null);
    }

    private void handleTimeEvent(MethodCall call, Result result) {
        String eventName = call.argument("eventName");
        mixpanel.timeEvent(eventName);
        result.success(null);
    }

    private void handleEventElapsedTime(MethodCall call, Result result) {
        String eventName = call.argument("eventName");
        result.success(mixpanel.eventElapsedTime(eventName));
    }

    private void handleReset(MethodCall call, Result result) {
        mixpanel.reset();
        result.success(null);
    }

    private void handleGetDistinctId(MethodCall call, Result result) {
        result.success(mixpanel.getDistinctId());
    }

    private void handleFlush(MethodCall call, Result result) {
        mixpanel.flush();
        result.success(null);
    }

    private void handleSet(MethodCall call, Result result) {
        Map<String, Object> mapProperties = call.<HashMap<String, Object>>argument("properties");
        JSONObject properties;
        try {
            properties = new JSONObject(mapProperties == null ? EMPTY_HASHMAP : mapProperties);
            properties = MixpanelFlutterHelper.getMergedProperties(properties, mixpanelProperties);
        } catch (JSONException e) {
            result.error("MixpanelFlutterException", e.getLocalizedMessage(), null);
            return;
        }
        mixpanel.getPeople().set(properties);
        result.success(null);
    }

    private void handleUnset(MethodCall call, Result result) {
        String propertyName = call.argument("name");
        mixpanel.getPeople().unset(propertyName);
        result.success(null);
    }

    private void handleSetOnce(MethodCall call, Result result) {
        Map<String, Object> mapProperties = call.<HashMap<String, Object>>argument("properties");
        JSONObject properties;
        try {
            properties = new JSONObject(mapProperties == null ? EMPTY_HASHMAP : mapProperties);
            properties = MixpanelFlutterHelper.getMergedProperties(properties, mixpanelProperties);
        } catch (JSONException e) {
            result.error("MixpanelFlutterException", e.getLocalizedMessage(), null);
            return;
        }
        mixpanel.getPeople().setOnce(properties);
        result.success(null);
    }

    private void handleTrackCharge(MethodCall call, Result result) {
        double charge = call.argument("amount");
        Map<String, Object> mapProperties = call.<HashMap<String, Object>>argument("properties");
        JSONObject properties;
        try {
            properties = new JSONObject(mapProperties == null ? EMPTY_HASHMAP : mapProperties);
            properties = MixpanelFlutterHelper.getMergedProperties(properties, mixpanelProperties);
        } catch (JSONException e) {
            result.error("MixpanelFlutterException", e.getLocalizedMessage(), null);
            return;
        }
        mixpanel.getPeople().trackCharge(charge, properties);
        result.success(null);
    }

    private void handleClearCharges(MethodCall call, Result result) {
        mixpanel.getPeople().clearCharges();
        result.success(null);
    }

    private void handleIncrement(MethodCall call, Result result) {
        Map<String, Number> properties = call.<HashMap<String, Number>>argument("properties");
        mixpanel.getPeople().increment(properties);
        result.success(null);
    }

    private void handleAppend(MethodCall call, Result result) {
        String name = call.argument("name");
        Object value = call.argument("value");
        mixpanel.getPeople().append(name, value);
        result.success(null);
    }

    private void handleDeleteUser(MethodCall call, Result result) {
        mixpanel.getPeople().deleteUser();
        result.success(null);
    }

    private void handleRemove(MethodCall call, Result result) {
        String name = call.argument("name");
        Object value = call.argument("value");
        mixpanel.getPeople().remove(name, value);
        result.success(null);
    }

    private void handleTrackWithGroups(MethodCall call, Result result) {
        String eventName = call.argument("eventName");
        Map<String, Object> eventProperties = call.<HashMap<String, Object>>argument("properties");
        Map<String, Object> eventGroups = call.<HashMap<String, Object>>argument("groups");
        mixpanel.trackWithGroups(eventName, eventProperties, eventGroups);
        result.success(null);
    }

    private void handleSetGroup(MethodCall call, Result result) {
        String groupKey = call.argument("groupKey");
        Object groupID = call.argument("groupID");
        mixpanel.setGroup(groupKey, groupID);
        result.success(null);
    }

    private void handleAddGroup(MethodCall call, Result result) {
        String groupKey = call.argument("groupKey");
        Object groupID = call.argument("groupID");
        mixpanel.addGroup(groupKey, groupID);
        result.success(null);
    }

    private void handleRemoveGroup(MethodCall call, Result result) {
        String groupKey = call.argument("groupKey");
        Object groupID = call.argument("groupID");
        mixpanel.removeGroup(groupKey, groupID);
        result.success(null);
    }

    private void handleDeleteGroup(MethodCall call, Result result) {
        String groupKey = call.argument("groupKey");
        Object groupID = call.argument("groupID");
        mixpanel.getGroup(groupKey, groupID).deleteGroup();
        result.success(null);
    }

    private void handleGroupSetProperties(MethodCall call, Result result) {
        String groupKey = call.argument("groupKey");
        Object groupID = call.argument("groupID");
        Map<String, Object> mapProperties = call.<HashMap<String, Object>>argument("properties");
        JSONObject properties = new JSONObject(mapProperties == null ? EMPTY_HASHMAP : mapProperties);
        mixpanel.getGroup(groupKey, groupID).set(properties);
        result.success(null);
    }

    private void handleGroupSetPropertyOnce(MethodCall call, Result result) {
        String groupKey = call.argument("groupKey");
        Object groupID = call.argument("groupID");
        Map<String, Object> mapProperties = call.<HashMap<String, Object>>argument("properties");
        JSONObject properties = new JSONObject(mapProperties == null ? EMPTY_HASHMAP : mapProperties);
        mixpanel.getGroup(groupKey, groupID).setOnce(properties);
        result.success(null);
    }

    private void handleGroupUnsetProperty(MethodCall call, Result result) {
        String groupKey = call.argument("groupKey");
        Object groupID = call.argument("groupID");
        String propertyName = call.argument("propertyName");
        mixpanel.getGroup(groupKey, groupID).unset(propertyName);
        result.success(null);
    }

    private void handleGroupRemovePropertyValue(MethodCall call, Result result) {
        String groupKey = call.argument("groupKey");
        Object groupID = call.argument("groupID");
        String name = call.argument("name");
        Object value = call.argument("value");
        mixpanel.getGroup(groupKey, groupID).remove(name, value);
        result.success(null);
    }

    private void handleGroupUnionProperty(MethodCall call, Result result) {
        String groupKey = call.argument("groupKey");
        Object groupID = call.argument("groupID");
        String name = call.argument("name");
        ArrayList<Object> value = call.argument("value");
        mixpanel.getGroup(groupKey, groupID).union(name, new JSONArray(value));
        result.success(null);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
    }
}

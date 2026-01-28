import Flutter
import UIKit
import Mixpanel

public class SwiftMixpanelFlutterPlugin: NSObject, FlutterPlugin {
    
    private var instance: MixpanelInstance?
    var token: String?
    var mixpanelProperties: [String: String]?
    let defaultFlushInterval = 60.0
    var trackAutomaticEvents: Bool?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let readWriter = MixpanelReaderWriter()
        let codec = FlutterStandardMethodCodec(readerWriter: readWriter)
        let channel = FlutterMethodChannel(name: "mixpanel_flutter", binaryMessenger: registrar.messenger(), codec: codec)
        let instance = SwiftMixpanelFlutterPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            handleInitialize(call, result: result)
            break
        case "setServerURL":
            handleSetServerURL(call, result: result)
            break
        case "setLoggingEnabled":
            handleSetLoggingEnabled(call, result: result)
            break
        case "setUseIpAddressForGeolocation":
            handleSetUseIpAddressForGeolocation(call, result: result)
            break
        case "hasOptedOutTracking":
            handleHasOptedOutTracking(call, result: result)
            break
        case "optInTracking":
            handleOptInTracking(call, result: result)
            break
        case "optOutTracking":
            handleOptOutTracking(call, result: result)
            break
        case "identify":
            handleIdentify(call, result: result)
            break
        case "alias":
            handleAlias(call, result: result)
            break
        case "track":
            handleTrack(call, result: result)
            break
        case "trackWithGroups":
            handleTrackWithGroups(call, result: result)
            break
        case "setGroup":
            handleSetGroup(call, result: result)
            break
        case "addGroup":
            handleAddGroup(call, result: result)
            break
        case "removeGroup":
            handleRemoveGroup(call, result: result)
            break
        case "deleteGroup":
            handleDeleteGroup(call, result: result)
            break
        case "registerSuperProperties":
            handleRegisterSuperProperties(call, result: result)
            break
        case "registerSuperPropertiesOnce":
            handleRegisterSuperPropertiesOnce(call, result: result)
            break
        case "unregisterSuperProperty":
            handleUnregisterSuperProperty(call, result: result)
            break
        case "getSuperProperties":
            handleGetSuperProperties(call, result: result)
            break
        case "clearSuperProperties":
            handleClearSuperProperties(call, result: result)
            break
        case "timeEvent":
            handleTimeEvent(call, result: result)
            break
        case "eventElapsedTime":
            handleEventElapsedTime(call, result: result)
            break
        case "reset":
            handleReset(call, result: result)
            break
        case "getDistinctId":
            handleGetDistinctId(call, result: result)
            break
        case "flush":
            handleFlush(call, result: result)
            break
        case "set":
            handleSet(call, result: result)
            break
        case "setOnce":
            handleSetOnce(call, result: result)
            break
        case "increment":
            handleIncrement(call, result: result)
            break
        case "append":
            handleAppend(call, result: result)
            break
        case "union":
            handleUnion(call, result: result)
            break
        case "remove":
            handleRemove(call, result: result)
            break
        case "unset":
            handleUnset(call, result: result)
            break
        case "trackCharge":
            handleTrackCharge(call, result: result)
            break
        case "clearCharges":
            handleClearCharges(call, result: result)
            break
        case "deleteUser":
            handleDeleteUser(call, result: result)
            break
        case "groupSetProperties":
            handleGroupSetProperties(call, result: result)
            break
        case "groupSetPropertyOnce":
            handleGroupSetPropertyOnce(call, result: result)
            break
        case "groupUnsetProperty":
            handleGroupUnsetProperty(call, result: result)
            break
        case "groupRemovePropertyValue":
            handleGroupRemovePropertyValue(call, result: result)
            break
        case "groupUnionProperty":
            handleGroupUnionProperty(call, result: result)
            break
        case "setFlushBatchSize":
            handleSetFlushBatchSize(call, result: result)
            break
        case "areFlagsReady":
            handleAreFlagsReady(call, result: result)
            break
        case "getVariant":
            handleGetVariant(call, result: result)
            break
        case "getVariantSync":
            handleGetVariantSync(call, result: result)
            break
        case "getVariantValue":
            handleGetVariantValue(call, result: result)
            break
        case "getVariantValueSync":
            handleGetVariantValueSync(call, result: result)
            break
        case "isEnabled":
            handleIsEnabled(call, result: result)
            break
        case "isEnabledSync":
            handleIsEnabledSync(call, result: result)
            break
        case "updateFlagsContext":
            handleUpdateFlagsContext(call, result: result)
            break
        default:
            result(FlutterMethodNotImplemented)
        }

        return
    }
    
    private func handleInitialize(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let token = arguments["token"] as? String
        let optOutTrackingDefault = arguments["optOutTrackingDefault"] as? Bool
        mixpanelProperties = arguments["mixpanelProperties"] as? [String: String]
        let superProperties = arguments["superProperties"] as? [String: Any]
        self.token = token
        let trackAutomaticEvents = arguments["trackAutomaticEvents"] as! Bool
        self.trackAutomaticEvents = trackAutomaticEvents

        // Check for feature flags configuration
        var featureFlagsEnabled = false
        var featureFlagsContext: [String: Any] = [:]
        if let featureFlags = arguments["featureFlags"] as? [String: Any],
           let enabled = featureFlags["enabled"] as? Bool, enabled {
            featureFlagsEnabled = true
            featureFlagsContext = featureFlags["context"] as? [String: Any] ?? [:]
        }

        let options = MixpanelOptions(
            token: token!,
            flushInterval: defaultFlushInterval,
            instanceName: token!,
            trackAutomaticEvents: trackAutomaticEvents,
            optOutTrackingByDefault: optOutTrackingDefault ?? false,
            superProperties: MixpanelTypeHandler.mixpanelProperties(properties: superProperties, mixpanelProperties: mixpanelProperties),
            featureFlagsEnabled: featureFlagsEnabled,
            featureFlagsContext: featureFlagsContext
        )
        instance = Mixpanel.initialize(options: options)

        result(nil)
    }
    
    private func getMixpanelInstance(_ token: String) -> MixpanelInstance? {
        if token.isEmpty {
            return nil
        }
        
        var instance = Mixpanel.getInstance(name: token)
        if instance == nil {
            instance = Mixpanel.initialize(token: token, trackAutomaticEvents: trackAutomaticEvents!, instanceName: token)
        }
        
        return instance
    }
    
    private func handleSetServerURL(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let serverURL = arguments["serverURL"] as! String
        instance?.serverURL = serverURL
        result(nil)
    }
    
    private func handleSetLoggingEnabled(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let loggingEnabled = arguments["loggingEnabled"] as! Bool
        instance?.loggingEnabled = loggingEnabled
        result(nil)
    }

    private func handleSetUseIpAddressForGeolocation(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let useIpAddressForGeolocation = arguments["useIpAddressForGeolocation"] as! Bool
        instance?.useIPAddressForGeoLocation = useIpAddressForGeolocation
        result(nil)
    }
    
    private func handleHasOptedOutTracking(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(instance?.hasOptedOutTracking())
    }
    
    private func handleOptInTracking(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        instance?.optInTracking(distinctId: nil, properties: MixpanelTypeHandler.mixpanelProperties(properties: mixpanelProperties))
        result(nil)
    }
    
    private func handleOptOutTracking(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        instance?.optOutTracking()
        result(nil)
    }
    
    private func handleIdentify(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let distinctId = arguments["distinctId"] as! String
        instance?.identify(distinctId: distinctId)
        result(nil)
    }
    
    private func handleAlias(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let alias = arguments["alias"] as! String
        let distinctId = arguments["distinctId"] as! String
        instance?.createAlias(alias, distinctId: distinctId)
        result(nil)
    }
    
    private func handleTrack(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let event = arguments["eventName"] as! String
        let properties = arguments["properties"] as? [String: Any]
        let mpProperties = MixpanelTypeHandler.mixpanelProperties(properties: properties, mixpanelProperties: mixpanelProperties)
        instance?.track(event: event, properties: mpProperties)
        result(nil)
    }
    
    private func handleTrackWithGroups(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let event = arguments["eventName"] as! String
        let properties = arguments["properties"] as? [String: Any]
        let groups = arguments["groups"] as? [String: Any]
        let mpProperties = MixpanelTypeHandler.mixpanelProperties(properties: properties, mixpanelProperties: mixpanelProperties)
        let mpGroups = MixpanelTypeHandler.mixpanelProperties(properties: groups)
        instance?.trackWithGroups(event: event, properties: mpProperties, groups: mpGroups)
        result(nil)
    }
    
    private func handleSetGroup(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let groupKey = arguments["groupKey"] as! String
        guard let mixpanelTypeGroupID = MixpanelTypeHandler.mixpanelTypeValue(arguments["groupID"] as Any) else {
            return
        }
        instance?.setGroup(groupKey: groupKey, groupID: mixpanelTypeGroupID)
        result(nil)
    }
    
    private func handleAddGroup(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let groupKey = arguments["groupKey"] as! String
        guard let mixpanelTypeGroupID = MixpanelTypeHandler.mixpanelTypeValue(arguments["groupID"] as Any) else {
            return
        }
        instance?.addGroup(groupKey: groupKey, groupID: mixpanelTypeGroupID)
        result(nil)
    }
    
    private func handleRemoveGroup(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let groupKey = arguments["groupKey"] as! String
        guard let mixpanelTypeGroupID = MixpanelTypeHandler.mixpanelTypeValue(arguments["groupID"] as Any) else {
            return
        }
        instance?.removeGroup(groupKey: groupKey, groupID: mixpanelTypeGroupID)
        result(nil)
    }
    
    private func handleRegisterSuperProperties(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let properties = arguments["properties"] as? [String: Any]
        instance?.registerSuperProperties(MixpanelTypeHandler.mixpanelProperties(properties: properties, mixpanelProperties: mixpanelProperties))
        result(nil)
    }
    
    private func handleRegisterSuperPropertiesOnce(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let properties = arguments["properties"] as? [String: Any]
        instance?.registerSuperPropertiesOnce(MixpanelTypeHandler.mixpanelProperties(properties: properties, mixpanelProperties: mixpanelProperties))
        result(nil)
    }
    
    private func handleUnregisterSuperProperty(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let propertyName = arguments["propertyName"] as! String
        instance?.unregisterSuperProperty(propertyName)
        result(nil)
    }
    
    private func handleGetSuperProperties(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(instance?.currentSuperProperties())
    }
    
    private func handleClearSuperProperties(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        instance?.clearSuperProperties()
        result(nil)
    }
    
    private func handleTimeEvent(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let event = arguments["eventName"] as! String
        instance?.time(event: event)
        result(nil)
    }
    
    private func handleEventElapsedTime(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let event = arguments["eventName"] as! String
        result(instance?.eventElapsedTime(event: event))
    }
    
    private func handleReset(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        instance?.reset()
        result(nil)
    }
    
    private func handleGetDistinctId(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(instance?.distinctId)
    }
    
    private func handleFlush(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        instance?.flush()
        result(nil)
    }
    
    // MARK: - People
    func handleSet(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let properties = arguments["properties"] as? [String: Any]
        instance?.people.set(properties: MixpanelTypeHandler.mixpanelProperties(properties: properties, mixpanelProperties: mixpanelProperties))
        result(nil)
    }
    
    private func handleSetOnce(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let properties = arguments["properties"] as? [String: Any]
        instance?.people.setOnce(properties: MixpanelTypeHandler.mixpanelProperties(properties: properties, mixpanelProperties: mixpanelProperties))
        result(nil)
    }
    
    private func handleUnset(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let propertyName = arguments["name"] as! String
        instance?.people.unset(properties: [propertyName])
        result(nil)
    }
    
    
    private func handleIncrement(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let properties = arguments["properties"] as? [String: Any]
        instance?.people.increment(properties: MixpanelTypeHandler.mixpanelProperties(properties: properties))
        result(nil)
    }
    
    private func handleAppend(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let properties = arguments["properties"] as? [String: Any]
        instance?.people.append(properties: MixpanelTypeHandler.mixpanelProperties(properties: properties))
        result(nil)
    }
    
    private func handleUnion(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let properties = arguments["properties"] as? [String: Any]
        instance?.people.union(properties: MixpanelTypeHandler.mixpanelProperties(properties: properties))
        result(nil)
    }
    
    private func handleRemove(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let properties = arguments["properties"] as? [String: Any]
        instance?.people.remove(properties: MixpanelTypeHandler.mixpanelProperties(properties: properties))
        result(nil)
    }
    
    private func handleTrackCharge(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let properties = arguments["properties"] as? [String: Any]
        let amount = arguments["amount"] as! Double
        instance?.people.trackCharge(amount: amount, properties: MixpanelTypeHandler.mixpanelProperties(properties: properties))
        result(nil)
    }
    
    private func handleClearCharges(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        instance?.people.clearCharges()
        result(nil)
    }
    
    private func handleDeleteUser(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        instance?.people.deleteUser()
        result(nil)
    }
    
    func mixpanelGroup(_ token: String, groupKey: String, groupID: Any) -> Group? {
        guard let instance = getMixpanelInstance(token) else {
            return nil
        }
        guard let mixpanelTypeGroupID = MixpanelTypeHandler.mixpanelTypeValue(groupID) else {
            return nil
        }
        return instance.getGroup(groupKey: groupKey, groupID: mixpanelTypeGroupID)
    }

    
    // MARK: - Group
    private func handleDeleteGroup(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        guard let token = arguments["token"] as? String else {
            return
        }
        guard let groupKey = arguments["groupKey"] as? String else {
            return
        }
        guard let groupID = arguments["groupID"] else {
            return
        }
        let group = mixpanelGroup(token, groupKey: groupKey, groupID: groupID)
        group?.deleteGroup()
        result(nil)
    }
    
    func handleGroupSetProperties(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        guard let token = arguments["token"] as? String else {
            return
        }
        guard let groupKey = arguments["groupKey"] as? String else {
            return
        }
        guard let groupID = arguments["groupID"] else {
            return
        }
        let properties = arguments["properties"] as? [String: Any]
        let group = mixpanelGroup(token, groupKey: groupKey, groupID: groupID)
        group?.set(properties:  MixpanelTypeHandler.mixpanelProperties(properties: properties))
        result(nil)
    }
    
    private func handleGroupSetPropertyOnce(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        guard let token = arguments["token"] as? String else {
            return
        }
        guard let groupKey = arguments["groupKey"] as? String else {
            return
        }
        guard let groupID = arguments["groupID"] else {
            return
        }
        let properties = arguments["properties"] as? [String: Any]
        let group = mixpanelGroup(token, groupKey: groupKey, groupID: groupID)
        group?.setOnce(properties:  MixpanelTypeHandler.mixpanelProperties(properties: properties))
        result(nil)
    }
    
    private func handleGroupUnsetProperty(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        guard let token = arguments["token"] as? String else {
            return
        }
        guard let groupKey = arguments["groupKey"] as? String else {
            return
        }
        guard let groupID = arguments["groupID"] else {
            return
        }
        let propertyName = arguments["propertyName"] as! String
        let group = mixpanelGroup(token, groupKey: groupKey, groupID: groupID)
        group?.unset(property: propertyName)
        result(nil)
    }
    
    private func handleGroupRemovePropertyValue(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        guard let token = arguments["token"] as? String else {
            return
        }
        guard let groupKey = arguments["groupKey"] as? String else {
            return
        }
        guard let groupID = arguments["groupID"] else {
            return
        }
        let name = arguments["name"] as! String
        let value = arguments["value"] as Any
        guard let mixpanelTypeValue = MixpanelTypeHandler.mixpanelTypeValue(value) else {
            return
        }
        let group = mixpanelGroup(token, groupKey: groupKey, groupID: groupID)
        group?.remove(key: name, value: mixpanelTypeValue)
        result(nil)
    }
    
    private func handleGroupUnionProperty(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        guard let token = arguments["token"] as? String else {
            return
        }
        guard let groupKey = arguments["groupKey"] as? String else {
            return
        }
        guard let groupID = arguments["groupID"] else {
            return
        }
        let name = arguments["name"] as! String
        let values = arguments["value"] as! [Any]
        let group = mixpanelGroup(token, groupKey: groupKey, groupID: groupID)
        group?.union(key: name, values: values.map() { MixpanelTypeHandler.mixpanelTypeValue($0)! })
        result(nil)
    }

    private func handleSetFlushBatchSize(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        let batchSize = arguments["flushBatchSize"] as! Int
        instance?.flushBatchSize = batchSize
        result(nil)
    }

    // MARK: - Feature Flags

    private func handleAreFlagsReady(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if instance == nil {
            NSLog("[Mixpanel] areFlagsReady called before Mixpanel was initialized, returning false")
        }
        result(instance?.flags.areFlagsReady() ?? false)
    }

    private func handleGetVariant(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        guard let flagName = arguments["flagName"] as? String, !flagName.isEmpty else {
            NSLog("[Mixpanel] getVariant called with missing or empty flagName, returning nil")
            result(nil)
            return
        }
        let fallbackMap = arguments["fallback"] as? [String: Any]
        let fallback = mapToFlagVariant(fallbackMap)
        guard let inst = instance else {
            NSLog("[Mixpanel] getVariant called before Mixpanel was initialized, returning fallback")
            result(flagVariantToMap(fallback))
            return
        }
        inst.flags.getVariant(flagName, fallback: fallback) { variant in
            result(self.flagVariantToMap(variant))
        }
    }

    private func handleGetVariantSync(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        guard let flagName = arguments["flagName"] as? String, !flagName.isEmpty else {
            NSLog("[Mixpanel] getVariantSync called with missing or empty flagName, returning nil")
            result(nil)
            return
        }
        let fallbackMap = arguments["fallback"] as? [String: Any]
        let fallback = mapToFlagVariant(fallbackMap)
        if instance == nil {
            NSLog("[Mixpanel] getVariantSync called before Mixpanel was initialized, returning fallback")
        }
        let variant = instance?.flags.getVariantSync(flagName, fallback: fallback) ?? fallback
        result(flagVariantToMap(variant))
    }

    private func handleGetVariantValue(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        guard let flagName = arguments["flagName"] as? String, !flagName.isEmpty else {
            NSLog("[Mixpanel] getVariantValue called with missing or empty flagName, returning nil")
            result(nil)
            return
        }
        let fallbackValue = arguments["fallbackValue"]
        let fallback = MixpanelFlagVariant(key: flagName, value: fallbackValue)
        guard let inst = instance else {
            NSLog("[Mixpanel] getVariantValue called before Mixpanel was initialized, returning fallback")
            result(fallbackValue)
            return
        }
        inst.flags.getVariant(flagName, fallback: fallback) { variant in
            result(variant.value)
        }
    }

    private func handleGetVariantValueSync(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        guard let flagName = arguments["flagName"] as? String, !flagName.isEmpty else {
            NSLog("[Mixpanel] getVariantValueSync called with missing or empty flagName, returning nil")
            result(nil)
            return
        }
        let fallbackValue = arguments["fallbackValue"]
        let fallback = MixpanelFlagVariant(key: flagName, value: fallbackValue)
        if instance == nil {
            NSLog("[Mixpanel] getVariantValueSync called before Mixpanel was initialized, returning fallback")
        }
        let variant = instance?.flags.getVariantSync(flagName, fallback: fallback) ?? fallback
        result(variant.value)
    }

    private func handleIsEnabled(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        guard let flagName = arguments["flagName"] as? String, !flagName.isEmpty else {
            NSLog("[Mixpanel] isEnabled called with missing or empty flagName, returning false")
            result(false)
            return
        }
        let fallbackValue = arguments["fallbackValue"] as? Bool ?? false
        let fallback = MixpanelFlagVariant(key: flagName, value: fallbackValue)
        guard let inst = instance else {
            NSLog("[Mixpanel] isEnabled called before Mixpanel was initialized, returning fallback")
            result(fallbackValue)
            return
        }
        inst.flags.getVariant(flagName, fallback: fallback) { variant in
            if let boolValue = variant.value as? Bool {
                result(boolValue)
            } else {
                if variant.value != nil {
                    NSLog("[Mixpanel] isEnabled flag '\(flagName)' has non-boolean value, returning fallback")
                }
                result(fallbackValue)
            }
        }
    }

    private func handleIsEnabledSync(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        guard let flagName = arguments["flagName"] as? String, !flagName.isEmpty else {
            NSLog("[Mixpanel] isEnabledSync called with missing or empty flagName, returning false")
            result(false)
            return
        }
        let fallbackValue = arguments["fallbackValue"] as? Bool ?? false
        let fallback = MixpanelFlagVariant(key: flagName, value: fallbackValue)
        if instance == nil {
            NSLog("[Mixpanel] isEnabledSync called before Mixpanel was initialized, returning fallback")
        }
        let variant = instance?.flags.getVariantSync(flagName, fallback: fallback) ?? fallback
        if let boolValue = variant.value as? Bool {
            result(boolValue)
        } else {
            if variant.value != nil {
                NSLog("[Mixpanel] isEnabledSync flag '\(flagName)' has non-boolean value, returning fallback")
            }
            result(fallbackValue)
        }
    }

    private func handleUpdateFlagsContext(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Note: The iOS SDK does not support updating feature flags context after initialization.
        // Context must be set during Mixpanel.initialize() via MixpanelOptions.
        // This method is a no-op on iOS but we log a warning to inform developers.
        NSLog("[Mixpanel] updateFlagsContext is not supported on iOS. Feature flags context must be set during initialization.")
        result(nil)
    }

    private func mapToFlagVariant(_ map: [String: Any]?) -> MixpanelFlagVariant {
        guard let map = map else {
            return MixpanelFlagVariant(key: "", value: nil)
        }
        let key = map["key"] as? String ?? ""
        let value = map["value"]
        return MixpanelFlagVariant(key: key, value: value)
    }

    private func flagVariantToMap(_ variant: MixpanelFlagVariant) -> [String: Any?] {
        return [
            "key": variant.key,
            "value": variant.value,
            "experimentId": variant.experimentID,
            "isExperimentActive": variant.isExperimentActive,
            "isQaTester": variant.isQATester
        ]
    }

}

let DATE_TIME: UInt8 = 128
let URI: UInt8 = 129

public class MixpanelReader : FlutterStandardReader {
    public override func readValue(ofType type: UInt8) -> Any? {
        switch type {
            case DATE_TIME:
                var value: Int64 = 0
                readBytes(&value, length: 8)
                return Date(timeIntervalSince1970: TimeInterval(value / 1000 ))
            case URI:
                let urlString = readUTF8()
                return URL(string: urlString)
            default:
                return super.readValue(ofType: type)
        }
    }
}

public class MixpanelWriter : FlutterStandardWriter {
    override public func writeValue(_ value: Any) {
        if ( value is Date ) {
            writeByte(DATE_TIME)
            let date = value as! Date
            let time = date.timeIntervalSince1970
            var ms = time * 1000.0
            writeBytes(&ms, length: 8)
        } else if ( value is URL ) {
            let url = value as! URL
            let urlString = url.absoluteString
            writeByte(URI)
            writeUTF8(urlString)
        } else {
            super.writeValue(value)
        }
    }
}

public class MixpanelReaderWriter : FlutterStandardReaderWriter {
    public override func writer(with data: NSMutableData) -> FlutterStandardWriter {
        return MixpanelWriter(data: data)
    }
    public override func reader(with data: Data) -> FlutterStandardReader {
        return MixpanelReader(data: data)
    }
}


import 'dart:async';
import 'package:flutter/services.dart';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

/// The primary class for integrating Mixpanel with your app.
class Mixpanel {
  static const MethodChannel _channel = const MethodChannel('mixpanel_flutter');
  static Map<String, String> _mixpanelProperties = {
    '\$lib_version': '1.1.0',
    'mp_lib': 'flutter',
  };

  final String _token;
  final People _people;

  Mixpanel(String token)
      : _token = token,
        _people = new People(token);

  ///
  ///  Initializes an instance of the API with the given project token.
  ///
  ///  * [token] your project token.
  ///  * [optOutTrackingDefault] Optional Whether or not Mixpanel can start tracking by default. See
  ///  optOutTracking()
  ///
  static Future<Mixpanel> init(String token,
      {bool optOutTrackingDefault = false}) async {
    var properties = <String, dynamic>{'token': token};

    properties['optOutTrackingDefault'] = optOutTrackingDefault;
    properties['mixpanelProperties'] = _mixpanelProperties;

    await _channel.invokeMethod<void>('initialize', properties);
    return Mixpanel(token);
  }

  /// Set the base URL used for Mixpanel API requests.
  /// Useful if you need to proxy Mixpanel requests. Defaults to https://api.mixpanel.com.
  /// To route data to Mixpanel's EU servers, set to https://api-eu.mixpanel.com
  /// - Note: This method will only work for iOS. For android, please refer to:
  /// https://developer.mixpanel.com/docs/android
  ///
  /// * [serverURL] the base URL used for Mixpanel API requests
  void setServerURL(String serverURL) {
    if (Platform.isIOS) {
      if (_MixpanelHelper.isValidString(serverURL)) {
        _channel.invokeMethod<void>(
            'setServerURL', <String, dynamic>{'serverURL': serverURL});
      } else {
        developer.log('`setServerURL` failed: serverURL cannot be blank',
            name: 'Mixpanel');
      }
    }
  }

  /// This allows enabling or disabling of all Mixpanel logs at run time.
  /// - Note: This method will only work for iOS. For android, please refer to:
  /// https://developer.mixpanel.com/docs/android
  /// All logging is disabled by default. Usually, this is only required if
  /// you are running into issues with the SDK that you want to debug
  ///
  /// * [loggingEnabled] whether to enable logging
  void setLoggingEnabled(bool loggingEnabled) {
    if (Platform.isIOS) {
      // ignore: unnecessary_null_comparison
      if (loggingEnabled != null) {
        _channel.invokeMethod<void>('setLoggingEnabled',
            <String, dynamic>{'loggingEnabled': loggingEnabled});
      } else {
        developer.log(
            '`setLoggingEnabled` failed: loggingEnabled cannot be blank',
            name: 'Mixpanel');
      }
    }
  }

  /// Will return true if the user has opted out from tracking.
  /// return true if user has opted out from tracking. Defaults to false.
  Future<bool?> hasOptedOutTracking() async {
    return await _channel.invokeMethod<bool>('hasOptedOutTracking');
  }

  /// Use this method to opt-in an already opted-out user from tracking. People updates and track
  /// calls will be sent to Mixpanel after using this method.
  /// This method will internally track an opt-in event to your project.
  void optInTracking() {
    _channel.invokeMethod<void>('optInTracking');
  }

  /// Use this method to opt-out a user from tracking. Events and people updates that haven't been
  /// flushed yet will be deleted. Use flush() before calling this method if you want
  /// to send all the queues to Mixpanel before.
  ///
  /// This method will also remove any user-related information from the device.
  void optOutTracking() {
    _channel.invokeMethod<void>('optOutTracking');
  }

  /// Associate all future calls to track() with the user identified by
  /// the given distinct id.
  ///
  /// <p>Calls to track() made before corresponding calls to identify
  /// will use an anonymous locally generated distinct id, which means it is best to call identify
  /// early to ensure that your Mixpanel funnels and retention analytics can continue to track the
  /// user throughout their lifetime. We recommend calling identify when the user authenticates.
  ///
  /// <p>Once identify is called, the local distinct id persists across restarts of
  /// your application.
  ///
  /// * [distinctId] a string uniquely identifying this user. Events sent to
  /// Mixpanel using the same disinct_id will be considered associated with the
  /// same visitor/customer for retention and funnel reporting, so be sure that the given
  /// value is globally unique for each individual user you intend to track.
  void identify(String distinctId) {
    if (_MixpanelHelper.isValidString(distinctId)) {
      _channel.invokeMethod<void>(
          'identify', <String, dynamic>{'distinctId': distinctId});
    } else {
      developer.log('`identify` failed: distinctId cannot be blank',
          name: 'Mixpanel');
    }
  }

  /// The alias method creates an alias which Mixpanel will use to remap one id to another.
  /// Multiple aliases can point to the same identifier.
  ///
  ///  `mixpane.alias("New ID", mixpane.distinctId)`
  ///  `mixpane.alias("Newer ID", mixpane.distinctId)`
  ///
  /// This call does not identify the user after. You must still call both identify() and
  /// People.identify() if you wish the new alias to be used for Events and People.
  ///
  ///  * [alias] A unique identifier that you want to use as an identifier for this user.
  ///  * [distinctId] the current distinct_id that alias will be mapped to.
  void alias(String alias, String distinctId) {
    if (!_MixpanelHelper.isValidString(alias)) {
      developer.log('`alias` failed: alias cannot be blank', name: 'mixpanel');
      return;
    }
    if (!_MixpanelHelper.isValidString(distinctId)) {
      developer.log('`alias` failed: distinctId cannot be blank',
          name: 'Mixpanel');
      return;
    }
    _channel.invokeMethod<void>(
        'alias', <String, dynamic>{'alias': alias, 'distinctId': distinctId});
  }

  /// Track an event.
  ///
  /// Every call to track eventually results in a data point sent to Mixpanel. These data points
  /// are what are measured, counted, and broken down to create your Mixpanel reports. Events
  /// have a string name, and an optional set of name/value pairs that describe the properties of
  /// that event.
  ///
  /// * [eventName] The name of the event to send
  /// * [properties] An optional map containing the key value pairs of the properties to include in this event.
  void track(String eventName, {Map<String, dynamic>? properties}) {
    if (_MixpanelHelper.isValidString(eventName)) {
      _channel.invokeMethod<void>('track',
          <String, dynamic>{'eventName': eventName, 'properties': properties});
    } else {
      developer.log('`track` failed: eventName cannot be blank',
          name: 'Mixpanel');
    }
  }

  /// Returns a Mixpanel People object that can be used to set and increment
  /// People Analytics properties.
  ///
  /// return an instance of People that you can use to update records in Mixpanel People Analytics
  People getPeople() {
    return this._people;
  }

  ///  Track an event with specific groups.
  ///
  ///  Every call to track eventually results in a data point sent to Mixpanel. These data points
  ///  are what are measured, counted, and broken down to create your Mixpanel reports. Events
  ///  have a string name, and an optional set of name/value pairs that describe the properties of
  ///  that event. Group key/value pairs are upserted into the property map before tracking.
  ///
  ///  * [eventName] The name of the event to send
  ///  * [properties] A Map containing the key value pairs of the properties to include in this event.
  ///  * [groups] A Map containing the group key value pairs for this event.
  void trackWithGroups(String eventName, Map<String, dynamic> properties,
      Map<String, dynamic> groups) {
    if (_MixpanelHelper.isValidString(eventName)) {
      _channel.invokeMethod<void>('trackWithGroups', <String, dynamic>{
        'eventName': eventName,
        'properties': properties,
        'groups': groups
      });
    } else {
      developer.log('`trackWithGroups` failed: eventName cannot be blank',
          name: 'Mixpanel');
    }
  }

  /// Set the group this user belongs to.
  ///
  /// * [groupKey] The property name associated with this group type (must already have been set up).
  /// * [groupID] The group the user belongs to.
  void setGroup(String groupKey, dynamic groupID) {
    if (_MixpanelHelper.isValidString(groupKey)) {
      _channel.invokeMethod<void>('setGroup',
          <String, dynamic>{'groupKey': groupKey, 'groupID': groupID});
    } else {
      developer.log('`setGroup` failed: groupKey cannot be blank',
          name: 'Mixpanel');
    }
  }

  /// Returns a MixpanelGroup object that can be used to set and increment
  /// Group Analytics properties.
  ///
  /// * [groupKey] String identifying the type of group (must be already in use as a group key)
  /// * [groupID] Object identifying the specific group
  /// return an instance of MixpanelGroup that you can use to update
  ///     records in Mixpanel Group Analytics
  MixpanelGroup getGroup(String groupKey, dynamic groupID) {
    return new MixpanelGroup(this._token, groupKey, groupID);
  }

  /// Add a group to this user's membership for a particular group key
  ///
  /// * [groupKey] The property name associated with this group type (must already have been set up).
  /// * [groupID] The new group the user belongs to.
  void addGroup(String groupKey, dynamic groupID) {
    if (_MixpanelHelper.isValidString(groupKey)) {
      _channel.invokeMethod<void>('addGroup',
          <String, dynamic>{'groupKey': groupKey, 'groupID': groupID});
    } else {
      developer.log('`addGroup` failed: groupKey cannot be blank',
          name: 'Mixpanel');
    }
  }

  /// Remove a group from this user's membership for a particular group key
  ///
  /// * [groupKey] The property name associated with this group type (must already have been set up).
  /// * [groupID] The group value to remove.
  void removeGroup(String groupKey, dynamic groupID) {
    if (_MixpanelHelper.isValidString(groupKey)) {
      _channel.invokeMethod<void>('removeGroup',
          <String, dynamic>{'groupKey': groupKey, 'groupID': groupID});
    } else {
      developer.log('`removeGroup` failed: groupKey cannot be blank',
          name: 'Mixpanel');
    }
  }

  /// Permanently deletes this group's record from Group Analytics.
  ///
  /// * [groupKey] String identifying the type of group (must be already in use as a group key)
  /// * [groupID] Object identifying the specific group
  ///
  /// Calling deleteGroup deletes an entire record completely. Any future calls
  /// to Group Analytics using the same group value will create and store new values.
  void deleteGroup(String groupKey, dynamic groupID) {
    if (_MixpanelHelper.isValidString(groupKey)) {
      _channel.invokeMethod<void>('deleteGroup',
          <String, dynamic>{'groupKey': groupKey, 'groupID': groupID});
    } else {
      developer.log('`deleteGroup` failed: groupKey cannot be blank',
          name: 'Mixpanel');
    }
  }

  /// Register properties that will be sent with every subsequent call to track().
  ///
  /// SuperProperties are a collection of properties that will be sent with every event to Mixpanel,
  /// and persist beyond the lifetime of your application.
  ///
  /// Setting a superProperty with registerSuperProperties will store a new superProperty,
  /// possibly overwriting any existing superProperty with the same name (to set a
  /// superProperty only if it is currently unset, use registerSuperPropertiesOnce())
  ///
  /// SuperProperties will persist even if your application is taken completely out of memory.
  /// to remove a superProperty, call unregisterSuperProperty() or clearSuperProperties()
  ///
  /// * [properties] A Map containing super properties to register
  void registerSuperProperties(Map<String, dynamic> properties) {
    _channel.invokeMethod<void>(
        'registerSuperProperties', <String, dynamic>{'properties': properties});
  }

  /// Register super properties for events, only if no other super property with the
  /// same names has already been registered.
  ///
  /// Calling registerSuperPropertiesOnce will never overwrite existing properties.
  ///
  /// * [properties] A Map containing the super properties to register.
  void registerSuperPropertiesOnce(Map<String, dynamic> properties) {
    _channel.invokeMethod<void>('registerSuperPropertiesOnce',
        <String, dynamic>{'properties': properties});
  }

  /// Remove a single superProperty, so that it will not be sent with future calls to track().
  ///
  /// If there is a superProperty registered with the given name, it will be permanently
  /// removed from the existing superProperties.
  /// To clear all superProperties, use clearSuperProperties()
  ///
  /// * [propertyName] name of the property to unregister
  void unregisterSuperProperty(String propertyName) {
    if (_MixpanelHelper.isValidString(propertyName)) {
      _channel.invokeMethod<void>('unregisterSuperProperty',
          <String, dynamic>{'propertyName': propertyName});
    } else {
      developer.log(
          '`unregisterSuperProperty` failed: propertyName cannot be blank',
          name: 'Mixpanel');
    }
  }

  /// Returns a Map of the user's current super properties
  ///
  /// SuperProperties are a collection of properties that will be sent with every event to Mixpanel,
  /// and persist beyond the lifetime of your application.
  ///
  /// return Super properties for this Mixpanel instance.
  Future<Map?> getSuperProperties() async {
    return await _channel.invokeMethod<Map>('getSuperProperties');
  }

  /// Erase all currently registered superProperties.
  ///
  /// Future tracking calls to Mixpanel will not contain the specific
  /// superProperties registered before the clearSuperProperties method was called.
  ///
  /// To remove a single superProperty, use unregisterSuperProperty()
  void clearSuperProperties() {
    _channel.invokeMethod<void>('clearSuperProperties');
  }

  /// Begin timing of an event. Calling timeEvent("Thing") will not send an event, but
  /// when you eventually call track("Thing"), your tracked event will be sent with a "$duration"
  /// property, representing the number of seconds between your calls.
  ///
  /// * [eventName] the name of the event to track with timing.
  void timeEvent(String eventName) {
    if (_MixpanelHelper.isValidString(eventName)) {
      _channel.invokeMethod<void>(
          'timeEvent', <String, dynamic>{'eventName': eventName});
    } else {
      developer.log('`timeEvent` failed: eventName cannot be blank',
          name: 'Mixpanel');
    }
  }

  /// Retrieves the time elapsed for the named event since timeEvent() was called.
  ///
  /// * [eventName] the name of the event to be tracked that was previously called with timeEvent()
  ///
  /// Time elapsed since timeEvent(String) was called for the given eventName.
  Future<double?> eventElapsedTime(String eventName) async {
    if (_MixpanelHelper.isValidString(eventName)) {
      return await _channel.invokeMethod<double>(
          'eventElapsedTime', <String, dynamic>{'eventName': eventName});
    } else {
      return 0;
    }
  }

  /// Clear super properties and generates a new random distinctId for this instance.
  /// Useful for clearing data when a user logs out.
  void reset() {
    _channel.invokeMethod<void>('reset');
  }

  /// Returns the current distinct id of the user.
  /// This is either the id automatically generated by the library or the id that has been passed by a call to identify().
  ///
  /// example of usage:
  ///
  /// ```
  ///    const distinctId = await mixpanel.getDistinctId();
  ///
  /// ```
  ///
  /// return Future<String> the distinct id associated with Mixpanel event and People Analytics
  Future<String?> getDistinctId() {
    return _channel.invokeMethod<String>('getDistinctId');
  }

  /// Push all queued Mixpanel events and People Analytics changes to Mixpanel servers.
  ///
  /// Events and People messages are pushed gradually throughout
  /// the lifetime of your application. This means that to ensure that all messages
  /// are sent to Mixpanel when your application is shut down, you will
  /// need to call flush() to let the Mixpanel library know it should
  /// send all remaining messages to the server.
  void flush() {
    _channel.invokeMethod('flush');
  }
}

/// Core class for using Mixpanel People Analytics features.
///
/// The People object is used to update properties in a user's People Analytics record,
/// and to manage the receipt of push notifications sent via Mixpanel Engage.
/// For this reason, it's important to call identify(String) on the People
/// object before you work with it. Once you call identify, the user identity will
/// persist across stops and starts of your application, until you make another
/// call to identify using a different id.
class People {
  static const MethodChannel _channel = const MethodChannel('mixpanel_flutter');

  final String _token;

  People(String token) : _token = token;

  /// Sets a single property with the given name and value for this user.
  /// The given name and value will be assigned to the user in Mixpanel People Analytics,
  /// possibly overwriting an existing property with the same name.
  ///
  /// * [prop] The name of the Mixpanel property. This must be a String, for example "Zip Code"
  /// * [to] The value of the Mixpanel property. For "Zip Code", this value might be the String "90210"
  ///
  void set(String prop, dynamic to) {
    if (_MixpanelHelper.isValidString(prop)) {
      Map<String, dynamic> properties = {prop: to};
      _channel.invokeMethod<void>('set',
          <String, dynamic>{'token': this._token, 'properties': properties});
    } else {
      developer.log('`people set` failed: prop cannot be blank',
          name: 'Mixpanel');
    }
  }

  /// Works just like set(), except it will not overwrite existing property values. This is useful for properties like "First login date".
  ///
  /// * [prop] The name of the Mixpanel property. This must be a String, for example "Zip Code"
  /// * [to] The value of the Mixpanel property. For "Zip Code", this value might be the String "90210"
  void setOnce(String prop, dynamic to) {
    if (_MixpanelHelper.isValidString(prop)) {
      Map<String, dynamic> properties = {prop: to};
      _channel.invokeMethod<void>('setOnce',
          <String, dynamic>{'token': this._token, 'properties': properties});
    } else {
      developer.log('`people setOnce` failed: prop cannot be blank',
          name: 'Mixpanel');
    }
  }

  /// Add the given amount to an existing property on the identified user. If the user does not already
  /// have the associated property, the amount will be added to zero. To reduce a property,
  /// provide a negative number for the value.
  ///
  /// * [prop] the People Analytics property that should have its value changed
  /// * [by] the amount to be added to the current value of the named property
  void increment(String prop, double by) {
    Map<String, dynamic> properties = {prop: by};
    if (_MixpanelHelper.isValidString(prop)) {
      _channel.invokeMethod<void>('increment',
          <String, dynamic>{'token': this._token, 'properties': properties});
    } else {
      developer.log('`people increment` failed: prop cannot be blank',
          name: 'Mixpanel');
    }
  }

  ///  Appends a value to a list-valued property. If the property does not currently exist,
  ///  it will be created as a list of one element. If the property does exist and doesn't
  ///  currently have a list value, the append will be ignored.
  ///  * [name] the People Analytics property that should have it's value appended to
  ///  * [value] the new value that will appear at the end of the property's list
  void append(String name, dynamic value) {
    if (_MixpanelHelper.isValidString(name)) {
      if (Platform.isIOS) {
        Map<String, dynamic> properties = {name: value};
        _channel.invokeMethod<void>('append',
            <String, dynamic>{'token': this._token, 'properties': properties});
      } else {
        _channel.invokeMethod<void>('append', <String, dynamic>{
          'token': this._token,
          'name': name,
          'value': value
        });
      }
    } else {
      developer.log('`people append` failed: name cannot be blank',
          name: 'Mixpanel');
    }
  }

  /// Adds values to a list-valued property only if they are not already present in the list.
  /// If the property does not currently exist, it will be created with the given list as it's value.
  /// If the property exists and is not list-valued, the union will be ignored.
  ///
  /// * [name] name of the list-valued property to set or modify
  /// * [value] an array of values to add to the property value if not already present
  void union(String name, List<dynamic> value) {
    if (_MixpanelHelper.isValidString(name)) {
      if (Platform.isIOS) {
        Map<String, dynamic> properties = {name: value};
        _channel.invokeMethod<void>('union',
            <String, dynamic>{'token': this._token, 'properties': properties});
      } else {
        _channel.invokeMethod<void>('union', <String, dynamic>{
          'token': this._token,
          'name': name,
          'value': value
        });
      }
    } else {
      developer.log('`people union` failed: name cannot be blank',
          name: 'Mixpanel');
    }
  }

  /// Remove value from a list-valued property only if they are already present in the list.
  /// If the property does not currently exist, the remove will be ignored.
  /// If the property exists and is not list-valued, the remove will be ignored.
  ///
  /// * [name] the People Analytics property that should have it's value removed from
  /// * [value] the value that will be removed from the property's list
  void remove(String name, dynamic value) {
    if (_MixpanelHelper.isValidString(name)) {
      _channel.invokeMethod<void>('remove', <String, dynamic>{
        'token': this._token,
        'name': name,
        'value': value
      });
    } else {
      developer.log('`people remove` failed: name cannot be blank',
          name: 'Mixpanel');
    }
  }

  /// permanently removes the property with the given name from the user's profile
  ///
  /// * [name] name of a property to unset
  void unset(String name) {
    if (_MixpanelHelper.isValidString(name)) {
      _channel.invokeMethod<void>(
          'unset', <String, dynamic>{'token': this._token, 'name': name});
    } else {
      developer.log('`people unset` failed: name cannot be blank',
          name: 'Mixpanel');
    }
  }

  /// Track a revenue transaction for the identified people profile.
  ///
  /// * [amount] the amount of money exchanged. Positive amounts represent purchases or income from the customer, negative amounts represent refunds or payments to the customer.
  /// * [properties] an optional collection of properties to associate with this transaction.
  void trackCharge(double amount, {Map<String, dynamic>? properties}) {
    // ignore: unnecessary_null_comparison
    if (amount != null) {
      _channel.invokeMethod<void>('trackCharge', <String, dynamic>{
        'token': this._token,
        'amount': amount,
        'properties': properties
      });
    } else {
      developer.log('`people trackCharge` failed: amount cannot be blank',
          name: 'Mixpanel');
    }
  }

  /// Permanently clear the whole transaction history for the identified people profile.
  void clearCharges() {
    _channel.invokeMethod<void>(
        'clearCharges', <String, dynamic>{'token': this._token});
  }

  /// Permanently deletes the identified user's record from People Analytics.
  ///
  /// Calling deleteUser deletes an entire record completely. Any future calls
  /// to People Analytics using the same distinct id will create and store new values.
  void deleteUser() {
    _channel.invokeMethod<void>(
        'deleteUser', <String, dynamic>{'token': this._token});
  }
}

/// Core class for using Mixpanel Group Analytics features.
///
/// The MixpanelGroup object is used to update properties in a group's Group Analytics record.
class MixpanelGroup {
  static const MethodChannel _channel = const MethodChannel('mixpanel_flutter');

  final String _token;
  final String _groupKey;
  final dynamic _groupID;

  MixpanelGroup(String token, String groupKey, dynamic groupID)
      : _token = token,
        _groupKey = groupKey,
        _groupID = groupID;

  /// Sets a single property with the given name and value for this group.
  /// The given name and value will be assigned to the user in Mixpanel Group Analytics,
  /// possibly overwriting an existing property with the same name.
  ///
  /// * [prop] The name of the Mixpanel property. This must be a String, for example "Zip Code"
  /// * [to] The value to set on the given property name. For "Zip Code", this value might be the String "90210"
  void set(String prop, String to) {
    if (_MixpanelHelper.isValidString(prop)) {
      Map<String, dynamic> properties = {prop: to};

      _channel.invokeMethod<void>('groupSetProperties', <String, dynamic>{
        'token': this._token,
        'groupKey': this._groupKey,
        'groupID': this._groupID,
        'properties': properties
      });
    } else {
      developer.log('`group set` failed: prop cannot be blank',
          name: 'Mixpanel');
    }
  }

  /// Works just like groupSet() except it will not overwrite existing property values. This is useful for properties like "First login date".
  ///
  /// * [prop] The name of the Mixpanel property. This must be a String, for example "Zip Code"
  /// * [to] The value to set on the given property name. For "Zip Code", this value might be the String "90210"
  void setOnce(String prop, String to) {
    if (_MixpanelHelper.isValidString(prop)) {
      Map<String, dynamic> properties = {prop: to};

      _channel.invokeMethod<void>('groupSetPropertyOnce', <String, dynamic>{
        'token': this._token,
        'groupKey': this._groupKey,
        'groupID': this._groupID,
        'properties': properties
      });
    } else {
      developer.log('`group setOnce` failed: prop cannot be blank',
          name: 'Mixpanel');
    }
  }

  /// Permanently removes the property with the given name from the group's profile
  ///
  /// * [prop] name of a property to unset
  void unset(String prop) {
    if (_MixpanelHelper.isValidString(prop)) {
      _channel.invokeMethod<void>('groupUnsetProperty', <String, dynamic>{
        'token': this._token,
        'groupKey': this._groupKey,
        'groupID': this._groupID,
        'propertyName': prop
      });
    } else {
      developer.log('`group unset` failed: prop cannot be blank',
          name: 'Mixpanel');
    }
  }

  /// Remove value from a list-valued property only if it is already present in the list.
  /// If the property does not currently exist, the remove will be ignored.
  /// If the property exists and is not list-valued, the remove will be ignored.
  ///
  /// * [name] the Group Analytics list-valued property that should have a value removed
  /// * [value] the value that will be removed from the list
  void remove(String name, dynamic value) {
    if (_MixpanelHelper.isValidString(name)) {
      _channel.invokeMethod<void>('groupRemovePropertyValue', <String, dynamic>{
        'token': this._token,
        'groupKey': this._groupKey,
        'groupID': this._groupID,
        'name': name,
        'value': value
      });
    } else {
      developer.log('`group remove` failed: name cannot be blank',
          name: 'Mixpanel');
    }
  }

  /// Adds values to a list-valued property only if they are not already present in the list.
  /// If the property does not currently exist, it will be created with the given list as its value.
  /// If the property exists and is not list-valued, the union will be ignored.
  ///
  /// * [name] name of the list-valued property to set or modify
  /// * [value] an array of values to add to the property value if not already present
  void union(String name, List<dynamic> value) {
    if (!_MixpanelHelper.isValidString(name)) {
      developer.log('`group union` failed: name cannot be blank',
          name: 'Mixpanel');
      return;
    }
    // ignore: unnecessary_null_comparison
    if (value == null) {
      developer.log('`group union` failed: value cannot be blank',
          name: 'Mixpanel');
      return;
    }
    _channel.invokeMethod<void>('groupUnionProperty', <String, dynamic>{
      'token': this._token,
      'groupKey': this._groupKey,
      'groupID': this._groupID,
      'name': name,
      'value': value
    });
  }
}

class _MixpanelHelper {
  static isValidString(String input) {
    // ignore: unnecessary_null_comparison
    return input != null && input.isNotEmpty;
  }
}

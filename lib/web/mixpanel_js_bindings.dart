import 'dart:js_interop';

@JS('mixpanel')
@staticInterop
class Mixpanel {}

@JS('MixpanelGroup')
@staticInterop
class MixpanelGroup {}

extension MixpanelGroupMethods on MixpanelGroup {
  external void set(JSAny? properties);

  @JS('group.set_once')
  external void set_once(String prop, JSAny? to);

  external void unset(String prop);

  external void remove(String name, JSAny? value);

  external void union(String name, JSArray values);
}

@JS('mixpanel.init')
external void init(String token, JSAny? config);

@JS('mixpanel.set_config')
external void set_config(JSAny? config);

@JS('mixpanel.has_opted_out_tracking')
external bool has_opted_out_tracking();

@JS('mixpanel.opt_in_tracking')
external void opt_in_tracking();

@JS('mixpanel.opt_out_tracking')
external void opt_out_tracking();

@JS('mixpanel.identify')
external void identify(String distinctId);

@JS('mixpanel.alias')
external void alias(String alias, String distinctId);

@JS('mixpanel.track')
external void track(String name, JSAny? properties);

@JS('mixpanel.track_with_groups')
external void track_with_groups(String event_name, JSAny? properties, JSAny? groups);

@JS('mixpanel.set_group')
external void set_group(String group_key, JSAny? group_ids);

@JS('mixpanel.add_group')
external void add_group(String group_key, JSAny? group_id);

@JS('mixpanel.remove_group')
external void remove_group(String group_key, JSAny? group_id);

@JS('mixpanel.get_group')
external MixpanelGroup get_group(String group_key, JSAny? group_id);

@JS('mixpanel.register')
external void register(JSAny? properties);

@JS('mixpanel.register_once')
external void register_once(JSAny? properties);

@JS('mixpanel.unregister')
external void unregister(String property);

@JS('mixpanel.time_event')
external void time_event(String event_name);

@JS('mixpanel.reset')
external void reset();

@JS('mixpanel.get_distinct_id')
external String get_distinct_id();

@JS('mixpanel.people.set')
external void people_set(JSAny? properties);

@JS('mixpanel.people.set_once')
external void people_set_once(JSAny? properties);

@JS('mixpanel.people.increment')
external void people_increment(JSAny? properties);

@JS('mixpanel.people.append')
external void people_append(JSAny? properties);

@JS('mixpanel.people.union')
external void people_union(JSAny? properties);

@JS('mixpanel.people.remove')
external void people_remove(JSAny? properties);

@JS('mixpanel.people.unset')
external void people_unset(JSAny? properties);

@JS('mixpanel.people.track_charge')
external void people_track_charge(double amount, JSAny? properties);

@JS('mixpanel.people.clear_charge')
external void people_clear_charge();

@JS('mixpanel.people.delete_users')
external void people_delete_users();

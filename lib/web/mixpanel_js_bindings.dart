@JS('mixpanel')
library mixpaneljs;

import 'package:js/js.dart';

@JS('init')
external void init(String token, Object? config);

@JS('set_config')
external void set_config(Object config);

@JS('get_config')
external Object get_config();

@JS('has_opted_out_tracking')
external bool has_opted_out_tracking();

@JS('opt_in_tracking')
external void opt_in_tracking();

@JS('opt_out_tracking')
external void opt_out_tracking();

@JS('identify')
external void identify(String distinctId);

@JS('alias')
external void alias(String alias, String distinctId);

@JS('track')
external void track(String name, Object? properties);

@JS('track_with_groups')
external void track_with_groups(
    String event_name, Object properties, Object groups);

@JS('set_group')
external void set_group(String group_key, Object group_ids);

@JS('add_group')
external void add_group(String group_key, Object group_id);

@JS('remove_group')
external void remove_group(String group_key, Object group_id);

@JS('get_group')
external MixpanelGroup get_group(String group_key, Object group_id);

@JS('register')
external void register(Object properties);

@JS('register_once')
external void register_once(Object properties);

@JS('unregister')
external void unregister(String property);

@JS('time_event')
external void time_event(String event_name);

@JS('reset')
external void reset();

@JS('get_distinct_id')
external String get_distinct_id();

@JS('people.set')
external void people_set(Object properties);

@JS('people.set_once')
external void people_set_once(Object properties);

@JS('people.increment')
external void people_increment(Object properties);

@JS('people.append')
external void people_append(Object properties);

@JS('people.union')
external void people_union(Object properties);

@JS('people.remove')
external void people_remove(Object properties);

@JS('people.unset')
external void people_unset(Object properties);

@JS('people.track_charge')
external void people_track_charge(double amount, Object? properties);

@JS('people.clear_charge')
external void people_clear_charge();

@JS('people.delete_users')
external void people_delete_users();

@JS()
class MixpanelGroup {
  @JS('group.set')
  external void set(Object properties);

  @JS('group.set_once')
  external void set_once(String prop, Object to);

  @JS('group.unset')
  external void unset(String prop);

  @JS('group.remove')
  external void remove(String name, Object value);

  @JS('group.union')
  external void union(String name, List<dynamic> values);
}

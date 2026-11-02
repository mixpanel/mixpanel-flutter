// The hierarchical groups scenarios from the Notion testing doc, one test per
// section and in the same order.
//
// Flutter builds no requests: each Dart call is forwarded over the
// `mixpanel_flutter` method channel to the native Android and Swift SDKs, or
// to mixpanel-js on web, and those SDKs apply the hierarchical groups rules
// and build the request. So this is a channel-contract suite: each test asserts
// the method-channel calls and arguments a scenario's Dart calls produce, or
// that no call is made where the Dart layer drops it. The request payloads and
// endpoints, and which calls the SDK drops as unsupported, are covered by the
// native and JS scenario suites.
//
// Edge cases beyond the doc live in the "Hierarchical groups" group of
// mixpanel_flutter_test.dart.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/codec/mixpanel_message_codec.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';

const String token = 'test token';
const String userId = 'my_user_id';
const String companyId = 'my_company_id';
const String teamId = 'my_team_id';

void main() {
  const MethodChannel channel = MethodChannel(
      'mixpanel_flutter', StandardMethodCodec(MixpanelMessageCodec()));
  final List<MethodCall> calls = <MethodCall>[];
  // What the native getIdentity returns; identify() sets it to the user
  Map<String, dynamic>? identityResponse;
  late Mixpanel mixpanel;

  TestWidgetsFlutterBinding.ensureInitialized();

  const Map<String, dynamic> identityArgs = <String, dynamic>{
    'identity': <String, dynamic>{
      'userId': userId,
      'companyId': companyId,
      'deviceId': null,
    },
  };

  Future<void> identify() async {
    await mixpanel.identifyWithIdentity(
        const MixpanelIdentity(userId: userId, companyId: companyId));
    identityResponse = <String, dynamic>{
      'userId': userId,
      'companyId': companyId,
      'deviceId': 'device_1',
    };
  }

  // Starts a scenario from what the steps before it set up, so it asserts only
  // its own calls
  void clearCalls() {
    calls.clear();
  }

  void expectCalls(List<Matcher> expected) {
    expect(calls, expected);
  }

  Matcher trackCall(String eventName, Map<String, dynamic>? properties) {
    return isMethodCall('track', arguments: <String, dynamic>{
      'eventName': eventName,
      'properties': properties,
    });
  }

  const Map<String, dynamic> hgEventProperties = <String, dynamic>{
    'source': 'hierarchical_groups_page',
  };

  // People append, union and remove send a properties map on iOS, macOS and
  // web, and a name and value on Android
  Map<String, dynamic> peopleListArgs(String name, dynamic value) {
    if (kIsWeb || Platform.isIOS || Platform.isMacOS) {
      return <String, dynamic>{
        'token': token,
        'properties': <String, dynamic>{name: value},
      };
    }
    return <String, dynamic>{'token': token, 'name': name, 'value': value};
  }

  Matcher groupPropertiesCall(String method, String groupKey, String groupId,
      Map<String, dynamic> properties) {
    return isMethodCall(method, arguments: <String, dynamic>{
      'token': token,
      'groupKey': groupKey,
      'groupID': groupId,
      'properties': properties,
    });
  }

  Matcher groupListCall(String method, String groupKey, String groupId,
      String name, dynamic value) {
    return isMethodCall(method, arguments: <String, dynamic>{
      'token': token,
      'groupKey': groupKey,
      'groupID': groupId,
      'name': name,
      'value': value,
    });
  }

  Matcher groupUnsetCall(String groupKey, String groupId, String prop) {
    return isMethodCall('groupUnsetProperty', arguments: <String, dynamic>{
      'token': token,
      'groupKey': groupKey,
      'groupID': groupId,
      'propertyName': prop,
    });
  }

  Matcher userGroupCall(String method, String groupKey, dynamic groupId) {
    return isMethodCall(method,
        arguments: <String, dynamic>{'groupKey': groupKey, 'groupID': groupId});
  }

  group('Hierarchical groups scenarios', () {
    setUp(() async {
      calls.clear();
      identityResponse = <String, dynamic>{
        'userId': null,
        'companyId': null,
        'deviceId': 'device_1',
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall m) async {
        calls.add(m);
        if (m.method == 'getIdentity') {
          return identityResponse;
        }
        return null;
      });
      mixpanel = await Mixpanel.init(token,
          trackAutomaticEvents: true, hierarchicalGroups: true);
      clearCalls();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('Track (Anonymous)', () async {
      await mixpanel.track('HG Event!', properties: hgEventProperties);

      expectCalls([trackCall('HG Event!', hgEventProperties)]);
    });

    test('Identify', () async {
      await identify();

      expectCalls([isMethodCall('identifyWithIdentity', arguments: identityArgs)]);
    });

    test('Track (Identified)', () async {
      await identify();
      clearCalls();
      await mixpanel.track('HG Event!', properties: hgEventProperties);

      expectCalls([trackCall('HG Event!', hgEventProperties)]);
    });

    test('Set User Property', () async {
      await identify();
      clearCalls();
      mixpanel.getPeople().set('plan', 'enterprise');

      expectCalls([
        isMethodCall('set', arguments: <String, dynamic>{
          'token': token,
          'properties': <String, dynamic>{'plan': 'enterprise'},
        }),
      ]);
    });

    test('Set Once User Property', () async {
      await identify();
      clearCalls();
      mixpanel.getPeople().setOnce('first_seen', '2026-10-27');

      expectCalls([
        isMethodCall('setOnce', arguments: <String, dynamic>{
          'token': token,
          'properties': <String, dynamic>{'first_seen': '2026-10-27'},
        }),
      ]);
    });

    test('Union User Property', () async {
      await identify();
      clearCalls();
      mixpanel.getPeople().union('devices', ['android']);

      expectCalls([
        isMethodCall('union', arguments: peopleListArgs('devices', ['android'])),
      ]);
    });

    test('Remove User Property', () async {
      await identify();
      clearCalls();
      mixpanel.getPeople().remove('devices', 'android');

      expectCalls([
        isMethodCall('remove', arguments: peopleListArgs('devices', 'android')),
      ]);
    });

    test('Unset User Property', () async {
      await identify();
      clearCalls();
      mixpanel.getPeople().unset('plan');

      expectCalls([
        isMethodCall('unset',
            arguments: <String, dynamic>{'token': token, 'name': 'plan'}),
      ]);
    });

    test('Delete User', () async {
      await identify();
      clearCalls();
      mixpanel.getPeople().deleteUser();

      expectCalls([
        isMethodCall('deleteUser', arguments: <String, dynamic>{'token': token}),
      ]);
    });

    // The unsupported people operations below are forwarded, and the native
    // and JS SDKs drop them

    test('Clear Charges (Unsupported)', () async {
      await identify();
      clearCalls();
      mixpanel.getPeople().clearCharges();

      expectCalls([
        isMethodCall('clearCharges',
            arguments: <String, dynamic>{'token': token}),
      ]);
    });

    test('Increment User Property (Unsupported)', () async {
      await identify();
      clearCalls();
      // Flutter's increment takes one property; there is no map form
      mixpanel.getPeople().increment('logins', 1.0);

      expectCalls([
        isMethodCall('increment', arguments: <String, dynamic>{
          'token': token,
          'properties': <String, dynamic>{'logins': 1.0},
        }),
      ]);
    });

    test('Append User Property (Unsupported)', () async {
      await identify();
      clearCalls();
      mixpanel.getPeople().append('history', 'opened_hg_page');

      expectCalls([
        isMethodCall('append',
            arguments: peopleListArgs('history', 'opened_hg_page')),
      ]);
    });

    test('Track Charge (Unsupported)', () async {
      await identify();
      clearCalls();
      mixpanel.getPeople().trackCharge(9.99);

      expectCalls([
        isMethodCall('trackCharge', arguments: <String, dynamic>{
          'token': token,
          'amount': 9.99,
          'properties': null,
        }),
      ]);
    });

    test('Set Company Property', () async {
      await identify();
      clearCalls();
      (await mixpanel.getCompany()).set('tier', 'enterprise');

      // getCompany reads the identified company from the native SDK
      expectCalls([
        isMethodCall('getIdentity', arguments: null),
        groupPropertiesCall('groupSetProperties', '\$company_id', companyId,
            <String, dynamic>{'tier': 'enterprise'}),
      ]);
    });

    test('Set Company Property through getGroup', () async {
      await identify();
      clearCalls();
      mixpanel.getGroup('\$company_id', companyId).set('tier', 'enterprise');

      expectCalls([
        groupPropertiesCall('groupSetProperties', '\$company_id', companyId,
            <String, dynamic>{'tier': 'enterprise'}),
      ]);
    });

    test('Set Once Company Property', () async {
      await identify();
      final company = await mixpanel.getCompany();
      clearCalls();
      company.setOnce('created', '2026-10-27');

      expectCalls([
        groupPropertiesCall('groupSetPropertyOnce', '\$company_id', companyId,
            <String, dynamic>{'created': '2026-10-27'}),
      ]);
    });

    test('Union Company Property', () async {
      await identify();
      final company = await mixpanel.getCompany();
      clearCalls();
      company.union('tags', ['android']);

      expectCalls([
        groupListCall('groupUnionProperty', '\$company_id', companyId, 'tags',
            ['android']),
      ]);
    });

    test('Remove Company Property', () async {
      await identify();
      final company = await mixpanel.getCompany();
      clearCalls();
      company.remove('tags', 'android');

      expectCalls([
        groupListCall('groupRemovePropertyValue', '\$company_id', companyId,
            'tags', 'android'),
      ]);
    });

    test('Unset Company Property', () async {
      await identify();
      final company = await mixpanel.getCompany();
      clearCalls();
      company.unset('tier');

      expectCalls([groupUnsetCall('\$company_id', companyId, 'tier')]);
    });

    test("Set User's Custom Group (setGroup)", () async {
      await identify();
      clearCalls();
      mixpanel.setGroup('team_id', teamId);

      expectCalls([userGroupCall('setGroup', 'team_id', teamId)]);
    });

    test('Track with Custom Group (trackWithGroups)', () async {
      await identify();
      clearCalls();
      // Flutter's trackWithGroups needs a properties map, so it is empty here
      await mixpanel.trackWithGroups(
          'HG Team Event!', <String, dynamic>{}, {'team_id': teamId});

      expectCalls([
        isMethodCall('trackWithGroups', arguments: <String, dynamic>{
          'eventName': 'HG Team Event!',
          'properties': <String, dynamic>{},
          'groups': <String, dynamic>{'team_id': teamId},
        }),
      ]);
    });

    test('Track (After setGroup)', () async {
      await identify();
      clearCalls();
      mixpanel.setGroup('team_id', teamId);
      await mixpanel.track('HG Event!', properties: hgEventProperties);

      // The native SDK adds team_id to the event as a super property
      expectCalls([
        userGroupCall('setGroup', 'team_id', teamId),
        trackCall('HG Event!', hgEventProperties),
      ]);
    });

    test("Remove User's Custom Group (removeGroup)", () async {
      await identify();
      mixpanel.setGroup('team_id', teamId);
      clearCalls();
      mixpanel.removeGroup('team_id', teamId);

      expectCalls([userGroupCall('removeGroup', 'team_id', teamId)]);
    });

    test('Set Custom Group Property', () async {
      await identify();
      clearCalls();
      mixpanel.getGroup('team_id', teamId).set('tier', 'enterprise');

      expectCalls([
        groupPropertiesCall('groupSetProperties', 'team_id', teamId,
            <String, dynamic>{'tier': 'enterprise'}),
      ]);
    });

    test('Set Once Custom Group Property', () async {
      await identify();
      clearCalls();
      mixpanel.getGroup('team_id', teamId).setOnce('created', '2026-10-27');

      expectCalls([
        groupPropertiesCall('groupSetPropertyOnce', 'team_id', teamId,
            <String, dynamic>{'created': '2026-10-27'}),
      ]);
    });

    test('Union Custom Group Property', () async {
      await identify();
      clearCalls();
      mixpanel.getGroup('team_id', teamId).union('tags', ['android']);

      expectCalls([
        groupListCall(
            'groupUnionProperty', 'team_id', teamId, 'tags', ['android']),
      ]);
    });

    test('Remove Custom Group Property', () async {
      await identify();
      clearCalls();
      mixpanel.getGroup('team_id', teamId).remove('tags', 'android');

      expectCalls([
        groupListCall(
            'groupRemovePropertyValue', 'team_id', teamId, 'tags', 'android'),
      ]);
    });

    test('Unset Custom Group Property', () async {
      await identify();
      clearCalls();
      mixpanel.getGroup('team_id', teamId).unset('tier');

      expectCalls([groupUnsetCall('team_id', teamId, 'tier')]);
    });

    // Flutter deletes a group through Mixpanel.deleteGroup, not on MixpanelGroup

    test('Delete Company', () async {
      await identify();
      clearCalls();
      mixpanel.deleteGroup('\$company_id', companyId);

      expectCalls([userGroupCall('deleteGroup', '\$company_id', companyId)]);
    });

    test('Delete Custom Group', () async {
      await identify();
      clearCalls();
      mixpanel.deleteGroup('team_id', teamId);

      expectCalls([userGroupCall('deleteGroup', 'team_id', teamId)]);
    });

    test('Reset', () async {
      await identify();
      mixpanel.setGroup('team_id', teamId);
      clearCalls();
      await mixpanel.reset();

      expectCalls([isMethodCall('reset', arguments: null)]);
    });

    test('Track (After Reset)', () async {
      await identify();
      mixpanel.setGroup('team_id', teamId);
      clearCalls();
      await mixpanel.reset();
      await mixpanel.track('HG Event!', properties: hgEventProperties);

      expectCalls([
        isMethodCall('reset', arguments: null),
        trackCall('HG Event!', hgEventProperties),
      ]);
    });

    test('Opt Out (Identified)', () async {
      await identify();
      clearCalls();
      mixpanel.optOutTracking();

      expectCalls([isMethodCall('optOutTracking', arguments: null)]);
    });

    test('Opt Out (Anonymous)', () async {
      mixpanel.optOutTracking();

      expectCalls([isMethodCall('optOutTracking', arguments: null)]);
    });

    test('Track (Opted Out)', () async {
      mixpanel.optOutTracking();
      clearCalls();
      await mixpanel.track('HG Event!', properties: hgEventProperties);

      // Forwarded; the native SDK drops events while opted out
      expectCalls([trackCall('HG Event!', hgEventProperties)]);
    });

    test('Opt In (Anonymous)', () async {
      mixpanel.optOutTracking();
      clearCalls();
      mixpanel.optInTracking();

      expectCalls([isMethodCall('optInTracking', arguments: null)]);
    });

    test('Opt In With Identity', () async {
      mixpanel.optOutTracking();
      clearCalls();
      await mixpanel.optInTrackingWithIdentity(
          const MixpanelIdentity(userId: userId, companyId: companyId));

      expectCalls([
        isMethodCall('optInTrackingWithIdentity', arguments: <String, dynamic>{
          ...identityArgs,
          'properties': null,
        }),
      ]);
    });

    // The unsupported identity and group calls below are forwarded, and the
    // native and JS SDKs drop them

    test('Identify Without Company (Unsupported)', () async {
      await mixpanel
          .identifyWithIdentity(const MixpanelIdentity(userId: userId));

      expectCalls([
        isMethodCall('identifyWithIdentity', arguments: <String, dynamic>{
          'identity': <String, dynamic>{
            'userId': userId,
            'companyId': null,
            'deviceId': null,
          },
        }),
      ]);
    });

    test('Identify With Distinct ID (Unsupported)', () async {
      await mixpanel.identify(userId);

      expectCalls([
        isMethodCall('identify',
            arguments: <String, dynamic>{'distinctId': userId}),
      ]);
    });

    test('Alias (Unsupported)', () async {
      await identify();
      clearCalls();
      // Flutter's alias needs a distinct id, so it is the user's id here
      mixpanel.alias('new_alias', userId);

      expectCalls([
        isMethodCall('alias', arguments: <String, dynamic>{
          'alias': 'new_alias',
          'distinctId': userId,
        }),
      ]);
    });

    test("Set User's Custom Groups With a List (Unsupported)", () async {
      await identify();
      clearCalls();
      mixpanel.setGroup('team_id', [teamId]);

      expectCalls([
        userGroupCall('setGroup', 'team_id', [teamId]),
      ]);
    });

    test("Add User's Custom Group (Unsupported)", () async {
      await identify();
      clearCalls();
      mixpanel.addGroup('team_id', teamId);

      expectCalls([userGroupCall('addGroup', 'team_id', teamId)]);
    });

    test('Set User Property Before Identify (Unsupported)', () async {
      mixpanel.getPeople().set('plan', 'enterprise');

      // Forwarded; the native SDK drops it
      expectCalls([
        isMethodCall('set', arguments: <String, dynamic>{
          'token': token,
          'properties': <String, dynamic>{'plan': 'enterprise'},
        }),
      ]);
    });

    test('Set Company Property Before Identify (Unsupported)', () async {
      (await mixpanel.getCompany()).set('tier', 'enterprise');

      // getCompany finds no company, so the Dart layer drops the update
      expectCalls([isMethodCall('getIdentity', arguments: null)]);
    });

    test('Set Company Property Without Hierarchical Groups (Unsupported)',
        () async {
      final mixpanelWithoutHG =
          await Mixpanel.init(token, trackAutomaticEvents: true);
      await identify();
      clearCalls();
      (await mixpanelWithoutHG.getCompany()).set('tier', 'enterprise');

      // getCompany is for hierarchical groups projects only, so the Dart layer
      // drops the update without asking the native SDK for the identity
      expect(calls, isEmpty);
    });

    test('Set Custom Group Property Before Identify (Unsupported)', () async {
      mixpanel.getGroup('team_id', teamId).set('tier', 'enterprise');

      // Forwarded; the native SDK drops it
      expectCalls([
        groupPropertiesCall('groupSetProperties', 'team_id', teamId,
            <String, dynamic>{'tier': 'enterprise'}),
      ]);
    });
  });
}

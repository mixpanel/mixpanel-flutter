import 'package:flutter/material.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:mixpanel_flutter_example/widget.dart';

// Hierarchical groups is an init-time option, so this page uses its own
// project rather than the one MixpanelManager initializes.
const String mixpanelHgProjectToken = '0d15128ec05aa2ba0fb3d45185f63a11';

// Filter the console on "HGDemo" to see each button's header line, followed
// by the SDK's own logs for that call.
const String _logTag = 'HGDemo';

void _log(String message) {
  debugPrint('[$_logTag] $message');
}

class HierarchicalGroupsScreen extends StatefulWidget {
  const HierarchicalGroupsScreen({Key? key}) : super(key: key);

  @override
  State<HierarchicalGroupsScreen> createState() =>
      _HierarchicalGroupsScreenState();
}

class _HgAction {
  const _HgAction(this.title, this.action);

  final String title;
  final Future<void> Function() action;
}

class _HierarchicalGroupsScreenState extends State<HierarchicalGroupsScreen> {
  static Future<Mixpanel>? _mixpanelFuture;

  final TextEditingController _userId =
      TextEditingController(text: 'tyler_flutter');
  final TextEditingController _companyId =
      TextEditingController(text: 'violet_tiger');
  final TextEditingController _teamId =
      TextEditingController(text: 'flutter_team');

  @override
  void initState() {
    super.initState();
    _mixpanelFuture ??= _initMixpanel();
  }

  @override
  void dispose() {
    _userId.dispose();
    _companyId.dispose();
    _teamId.dispose();
    super.dispose();
  }

  static Future<Mixpanel> _initMixpanel() async {
    // No automatic events, so each flush sends only what the button's call queued
    final mixpanel = await Mixpanel.init(mixpanelHgProjectToken,
        trackAutomaticEvents: false, hierarchicalGroups: true);
    mixpanel.setLoggingEnabled(true);
    return mixpanel;
  }

  MixpanelIdentity get _identity =>
      MixpanelIdentity(userId: _userId.text, companyId: _companyId.text);

  // The same group profile operations, for the company and for the custom
  // team_id group
  List<_HgAction> _groupActions(
      Mixpanel mixpanel,
      String label,
      Future<MixpanelGroup?> Function() group,
      Future<void> Function() deleteGroup) {
    return [
      _HgAction('$label: Set Property', () async {
        (await group())?.set('tier', 'enterprise');
      }),
      _HgAction('$label: Set Property Once', () async {
        (await group())?.setOnce('created', '2026-10-27');
      }),
      _HgAction('$label: Union Property', () async {
        (await group())?.union('tags', ['flutter']);
      }),
      _HgAction('$label: Remove Property', () async {
        (await group())?.remove('tags', 'flutter');
      }),
      _HgAction('$label: Unset Property', () async {
        (await group())?.unset('tier');
      }),
      _HgAction('$label: Delete Group', deleteGroup),
    ];
  }

  List<_HgAction> _actions(Mixpanel mixpanel) {
    final people = mixpanel.getPeople();
    return [
      // Identity
      _HgAction('Identify', () async {
        await mixpanel.identifyWithIdentity(_identity);
      }),
      _HgAction('Invalid: Identify Without Company', () async {
        await mixpanel
            .identifyWithIdentity(MixpanelIdentity(userId: _userId.text));
      }),
      _HgAction('Invalid: Identify With Distinct ID', () async {
        await mixpanel.identify(_userId.text);
      }),
      _HgAction('Invalid: Alias', () async {
        mixpanel.alias('new_alias', _userId.text);
      }),
      _HgAction('Show Identity', () async {
        final identity = await mixpanel.getIdentity();
        final optedOut = await mixpanel.hasOptedOutTracking();
        final superProperties = await mixpanel.getSuperProperties();
        _log('identity=$identity optedOut=$optedOut '
            'superProperties=$superProperties');
      }),

      // Opt out and in
      _HgAction('Opt Out', () async {
        mixpanel.optOutTracking();
      }),
      _HgAction('Opt In', () async {
        mixpanel.optInTracking();
      }),
      _HgAction('Opt In With Identity', () async {
        await mixpanel.optInTrackingWithIdentity(_identity);
      }),

      // Events
      _HgAction('Track Event', () async {
        await mixpanel.track('HG Event!',
            properties: {'source': 'hierarchical_groups_page'});
      }),
      _HgAction('Set Team Group', () async {
        mixpanel.setGroup('team_id', _teamId.text);
      }),
      _HgAction('Invalid: Set Team Groups (List)', () async {
        mixpanel.setGroup('team_id', [_teamId.text]);
      }),
      _HgAction('Invalid: Add Team Group', () async {
        mixpanel.addGroup('team_id', _teamId.text);
      }),
      _HgAction('Remove Team Group', () async {
        mixpanel.removeGroup('team_id', _teamId.text);
      }),
      _HgAction('Track With Team Group', () async {
        await mixpanel
            .trackWithGroups('HG Team Event!', {}, {'team_id': _teamId.text});
      }),

      // User profile ($user_id group profile)
      _HgAction('User: Set Property', () async {
        people.set('plan', 'enterprise');
      }),
      _HgAction('User: Set Property Once', () async {
        people.setOnce('first_seen', '2026-10-27');
      }),
      _HgAction('User: Union Property', () async {
        people.union('devices', ['ios', 'flutter']);
      }),
      _HgAction('User: Remove Property', () async {
        people.remove('devices', 'flutter');
      }),
      _HgAction('User: Unset Property', () async {
        people.unset('plan');
      }),
      _HgAction('Invalid: User Clear Charges', () async {
        people.clearCharges();
      }),
      _HgAction('User: Delete User', () async {
        people.deleteUser();
      }),

      // User profile operations the $user_id group profile has no
      // equivalent for, dropped with a log
      _HgAction('Invalid: User Increment', () async {
        people.increment('logins', 1);
      }),
      _HgAction('Invalid: User Append', () async {
        people.append('history', 'opened_hg_page');
      }),
      _HgAction('Invalid: User Track Charge', () async {
        people.trackCharge(9.99);
      }),

      ..._groupActions(mixpanel, 'Company', mixpanel.getCompany, () async {
        final companyId = (await mixpanel.getIdentity()).companyId;
        if (companyId == null || companyId.isEmpty) {
          _log('No company identified, nothing to delete');
          return;
        }
        mixpanel.deleteGroup('\$company_id', companyId);
      }),
      ..._groupActions(mixpanel, 'Team',
          () async => mixpanel.getGroup('team_id', _teamId.text), () async {
        mixpanel.deleteGroup('team_id', _teamId.text);
      }),

      _HgAction('Flush', () async {
        await mixpanel.flush();
      }),
      _HgAction('Reset', () async {
        await mixpanel.reset();
      }),
    ];
  }

  Widget _textField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xff4f44e0),
        title: const Text('Hierarchical Groups'),
      ),
      body: FutureBuilder<Mixpanel>(
        future: _mixpanelFuture,
        builder: (context, snapshot) {
          final mixpanel = snapshot.data;
          if (mixpanel == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 20),
            children: [
              _textField(_userId, 'User ID'),
              _textField(_companyId, 'Company ID'),
              _textField(_teamId, 'Team ID'),
              const SizedBox(height: 12),
              for (final hgAction in _actions(mixpanel))
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: MixpanelButton(
                    text: hgAction.title,
                    onPressed: () async {
                      _log('===== ${hgAction.title} =====');
                      await hgAction.action();
                      // Flush after every call so its requests show up on
                      // their own
                      await mixpanel.flush();
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

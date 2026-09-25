import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';

import 'analytics.dart';

/// Manual QA fixtures. Only the selected section/case is mounted so fixtures
/// do not exhaust the SDK's traversal budget or affect other response checks.
class FrustrationSignalsScreen extends StatefulWidget {
  const FrustrationSignalsScreen({Key? key}) : super(key: key);

  @override
  State<FrustrationSignalsScreen> createState() =>
      _FrustrationSignalsScreenState();
}

class _FrustrationSignalsScreenState extends State<FrustrationSignalsScreen> {
  late final Future<Mixpanel> _instance = MixpanelManager.init();
  int _section = 0;
  int _idCase = 0;
  bool _switch = false;
  bool _checkbox = false;
  double _slider = 0.5;
  String _response = 'AAAA';
  static const _sections = [
    'Element ID resolution',
    'Privacy: labels, text and keys',
    'Dead clicks',
    'Rage clicks',
    'Manual signals',
  ];

  Widget _identified(String id, Widget child) =>
      Semantics(identifier: id, child: child);

  Widget _button(Widget child) =>
      ElevatedButton(onPressed: () {}, child: child);

  Widget _plain(String text) => Padding(
        padding: const EdgeInsets.all(20),
        child: Text(text, style: const TextStyle(fontSize: 18)),
      );

  Widget _fixture(String title, String expected, Widget target) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(expected),
              const SizedBox(height: 16),
              Center(child: target),
            ],
          ),
        ),
      );

  List<String> get _idCases => [
        for (var mask = 0; mask < 8; mask++)
          'Owner ${mask & 1 != 0 ? "ID" : "none"} / '
              'child ${mask & 2 != 0 ? "ID" : "none"} / '
              'ancestor ${mask & 4 != 0 ? "ID" : "none"}',
        'Noninteractive text with ID',
        'Noninteractive text without ID',
        'Nested owners: inner ID wins',
        'Nested owners: no borrowing outer ID',
        'Nearest of two semantic IDs wins',
        'Empty ID falls through to ancestor',
        'Whitespace ID falls through to ancestor',
        'Overlong ID falls through to ancestor',
        'Overlong ID without ancestor uses fallback',
        'Ancestor beyond lookup depth uses fallback',
        'Icon child ID must not replace button ID',
        'Cupertino button owner ID',
        'InkWell owner ID',
        'GestureDetector owner ID',
        'Disabled button owner ID',
        'Sibling controls with structural IDs',
        'Noninteractive text inherits ancestor ID',
      ];

  Widget _idResolution() {
    late Widget target;
    late String expected;
    if (_idCase < 8) {
      final owner = _idCase & 1 != 0;
      final child = _idCase & 2 != 0;
      final ancestor = _idCase & 4 != 0;
      Widget label = const Text('Tap the child text');
      if (child) label = _identified('id_child_ignored', label);
      target = _button(label);
      if (owner) target = _identified('id_owner', target);
      target = Padding(padding: const EdgeInsets.all(8), child: target);
      if (ancestor) target = _identified('id_ancestor', target);
      expected =
          'Expected el_id: ${owner ? "id_owner" : ancestor ? "id_ancestor" : "ElevatedButton_<structural hash>"}. '
          'The child ID must never name the owning button.';
    } else {
      switch (_idCase) {
        case 8:
          target = _identified('id_plain', _plain('Plain text with ID'));
          expected = 'Expected el_id: id_plain. No interactive owner.';
          break;
        case 9:
          target = _plain('Plain text without ID');
          expected =
              'Expected: a structural RichText_<hash> or Text_<hash> ID; never the displayed text.';
          break;
        case 10:
        case 11:
          Widget inner = GestureDetector(
            onTap: () {},
            child: _plain('Tap inner gesture target'),
          );
          if (_idCase == 10) inner = _identified('id_inner', inner);
          target = _identified('id_outer', _button(inner));
          expected = _idCase == 10
              ? 'Expected el_id: id_inner; target GestureDetector.'
              : 'Expected GestureDetector_<hash>. Must not borrow id_outer across the outer button.';
          break;
        case 12:
          target = _identified('id_far',
              _identified('id_near', _button(const Text('Nearest ID'))));
          expected = 'Expected el_id: id_near.';
          break;
        case 13:
        case 14:
        case 15:
        case 16:
          final invalid = _idCase == 13
              ? ''
              : _idCase == 14
                  ? '   '
                  : List.filled(257, 'x').join();
          target =
              _identified(invalid, _button(const Text('Invalid identifier')));
          if (_idCase != 16) target = _identified('id_valid_ancestor', target);
          expected = _idCase == 16
              ? 'Expected ElevatedButton_<hash>; the 257-character ID is ignored.'
              : 'Expected el_id: id_valid_ancestor; the invalid nearer ID is ignored.';
          break;
        case 17:
          target = _button(const Text('Distant ID'));
          for (var i = 0; i < 12; i++) {
            target = Padding(padding: EdgeInsets.zero, child: target);
          }
          target = _identified('id_too_far', target);
          expected =
              'Expected ElevatedButton_<hash>. id_too_far is outside the 11-element lookup window.';
          break;
        case 18:
          target = _identified(
              'id_icon_button',
              IconButton(
                onPressed: () {},
                icon: _identified(
                    'id_icon_child_ignored', const Icon(Icons.star)),
              ));
          expected =
              'Expected el_id: id_icon_button, never id_icon_child_ignored.';
          break;
        case 19:
          target = _identified(
              'id_cupertino',
              CupertinoButton(
                  onPressed: () {}, child: const Text('Cupertino')));
          expected = 'Expected el_id: id_cupertino; target CupertinoButton.';
          break;
        case 20:
          target = _identified(
              'id_inkwell', InkWell(onTap: () {}, child: _plain('InkWell')));
          expected = 'Expected el_id: id_inkwell; target InkWell.';
          break;
        case 21:
          target = _identified('id_gesture',
              GestureDetector(onTap: () {}, child: _plain('GestureDetector')));
          expected = 'Expected el_id: id_gesture; target GestureDetector.';
          break;
        case 22:
          target = _identified('id_disabled',
              const ElevatedButton(onPressed: null, child: Text('Disabled')));
          expected = 'Expected click with el_id id_disabled; no dead click.';
          break;
        case 23:
          target = Row(mainAxisSize: MainAxisSize.min, children: [
            _button(const Text('Left')),
            const SizedBox(width: 12),
            _button(const Text('Right')),
          ]);
          expected =
              'Tap both. Expected distinct ElevatedButton_<hash> IDs, stable when retapping the same unchanged target.';
          break;
        default:
          target = _identified(
              'id_plain_ancestor',
              Padding(
                  padding: const EdgeInsets.all(8),
                  child: _plain('Inherited ID')));
          expected = 'Expected el_id: id_plain_ancestor.';
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text(
          'Select each case and tap only its target. Owner means an ID on '
          'Semantics wrapping the interactive control; child means an ID inside it.'),
      DropdownButton<int>(
        isExpanded: true,
        value: _idCase,
        items: [
          for (var i = 0; i < _idCases.length; i++)
            DropdownMenuItem(
                value: i,
                child: Text('${i + 1}. ${_idCases[i]}',
                    overflow: TextOverflow.ellipsis))
        ],
        onChanged: (value) {
          if (value != null) setState(() => _idCase = value);
        },
      ),
      _fixture(_idCases[_idCase], expected, target),
    ]);
  }

  Widget _privacy() => Column(children: [
        const Text(
            'These are synthetic privacy sentinels. Inspect \$el_id in emitted '
            'events: it must never contain LEAK_TEXT, LEAK_LABEL, LEAK_KEY, '
            'LEAK_INPUT, or LEAK_PASSWORD. No on-screen pass/fail is claimed; '
            'verify the actual payload in SDK logs or Mixpanel.'),
        _fixture(
            'Text only, no identifier',
            'Expected structural ID; never LEAK_TEXT.',
            _plain('LEAK_TEXT_private@example.test')),
        _fixture(
            'Accessibility label only',
            'Flutter Semantics.label is the accessibility label. Expected structural ID; never LEAK_LABEL.',
            Semantics(
                label: 'LEAK_LABEL_private@example.test',
                child: _button(const Text('Label fixture')))),
        _fixture(
            'Text + label + key, no identifier',
            'Expected structural ID. None of the three sentinels may enter el_id.',
            Semantics(
                label: 'LEAK_LABEL_combined',
                child: ElevatedButton(
                    key: const ValueKey('LEAK_KEY_private'),
                    onPressed: () {},
                    child: const Text('LEAK_TEXT_combined')))),
        _fixture(
            'Explicit safe identifier + private label/text',
            'Expected el_id: privacy_safe_id. Explicit identifiers are developer supplied and are not sanitized.',
            Semantics(
                identifier: 'privacy_safe_id',
                label: 'LEAK_LABEL_explicit',
                child: _button(const Text('LEAK_TEXT_explicit')))),
        _fixture(
            'Editable text',
            'Tap and edit. No value or label in el_id; no dead click.',
            const SizedBox(
                width: 260,
                child: TextField(
                    decoration: InputDecoration(
                        labelText: 'LEAK_LABEL_input',
                        hintText: 'Type LEAK_INPUT here')))),
        _fixture(
            'Password',
            'Enter LEAK_PASSWORD, then tap the field again. No value in el_id; no dead click.',
            const SizedBox(
                width: 260,
                child: TextField(
                    obscureText: true,
                    decoration:
                        InputDecoration(labelText: 'Password fixture')))),
      ]);

  Widget _dead() => Column(children: [
        const Text(
            'Tap once, release, then wait at least 500 ms without scrolling '
            'or touching anything else. A new tap or meaningful UI response cancels '
            'the previous pending check. Inspect \$mp_dead_click events.'),
        _fixture(
            'Interactive, no response',
            'Expected click + one dead click after the deadline.',
            _identified(
                'dead_interactive', _button(const Text('No-op button')))),
        _fixture(
            'Interactive, label response',
            'Expected click, no dead click. Label below changes immediately.',
            _identified(
                'dead_with_response',
                ElevatedButton(
                    onPressed: () => setState(() =>
                        _response = _response == 'AAAA' ? 'BBBB' : 'AAAA'),
                    child: const Text('Change label')))),
        Text(_response),
        _fixture('Noninteractive text', 'Expected click; no dead click.',
            _identified('dead_plain', _plain('No tap handler'))),
        _fixture(
            'Disabled button',
            'Expected click; no dead click.',
            _identified(
                'dead_disabled',
                const ElevatedButton(
                    onPressed: null, child: Text('Disabled button')))),
        _fixture(
            'Switch feedback',
            'Toggle it. Expected click; no dead click.',
            _identified(
                'dead_switch',
                Switch(
                    value: _switch,
                    onChanged: (value) => setState(() => _switch = value)))),
        _fixture(
            'Checkbox feedback',
            'Toggle it. Expected click; no dead click.',
            _identified(
                'dead_checkbox',
                Checkbox(
                    value: _checkbox,
                    onChanged: (value) =>
                        setState(() => _checkbox = value ?? false)))),
        _fixture(
            'Slider feedback',
            'Tap the track. Expected no dead click. Dragging is not a click.',
            _identified(
                'dead_slider',
                SizedBox(
                    width: 260,
                    child: Slider(
                        value: _slider,
                        onChanged: (value) =>
                            setState(() => _slider = value))))),
        _fixture(
            'Input field feedback',
            'Focus, type, then tap again. Expected no dead click, including while already focused.',
            _identified(
                'dead_input',
                const SizedBox(
                    width: 260,
                    child: TextField(
                        decoration:
                            InputDecoration(labelText: 'Input feedback'))))),
      ]);

  Widget _rage() => Column(children: [
        const Text(
            'Tap the same point four times within 1,000 ms (within 44 logical '
            'pixels). Expected four clicks and one rage click. Eight rapid taps '
            'should produce two rage clicks. After a pause longer than 1,000 ms, '
            'three taps must not produce a rage click. Avoid scrolling between taps.'),
        _fixture(
            'Interactive rage target',
            'Expected \$mp_rage_click with el_id rage_interactive. The no-op button can also produce a dead click after the final tap.',
            _identified(
                'rage_interactive', _button(const Text('Rage tap button')))),
        _fixture(
            'Noninteractive rage target',
            'Expected \$mp_rage_click with el_id rage_plain. No dead click.',
            _identified('rage_plain', _plain('Rage tap this plain text'))),
      ]);

  Widget _manual(Autocapture autocapture) => Column(children: [
        const Text(
            'These emit synthetic manual signals in addition to any automatic '
            'capture. Use the other sections to verify automatic detection.'),
        for (final kind in ['click', 'rage_click', 'dead_click'])
          _fixture(
              'Manual $kind',
              'Sends one requested signal with el_id manual_$kind.',
              GestureDetector(
                  onTapUp: (details) {
                    final event = ClickEvent(
                        x: details.globalPosition.dx,
                        y: details.globalPosition.dy,
                        elementId: 'manual_$kind',
                        tagName: 'GestureDetector',
                        role: 'Button');
                    if (kind == 'rage_click') {
                      autocapture.trackRageClick(event);
                    } else if (kind == 'dead_click') {
                      autocapture.trackDeadClick(event);
                    } else {
                      autocapture.trackClick(event);
                    }
                  },
                  child: _plain('Send manual $kind'))),
      ]);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Frustration signals — Beta')),
        body: FutureBuilder<Mixpanel>(
            future: _instance,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                    child: Text(
                        'Mixpanel initialization failed. Check the example configuration.'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView(padding: const EdgeInsets.all(16), children: [
                const Text('Automatic QA • Android / iOS / macOS / web\n'
                    'Use the configured project’s events or SDK logs to compare actual '
                    'payloads against expectations. Section selectors also generate '
                    'events; identify fixtures using the IDs below. Let transitions settle before tapping.'),
                DropdownButton<int>(
                    isExpanded: true,
                    value: _section,
                    items: [
                      for (var i = 0; i < _sections.length; i++)
                        DropdownMenuItem(value: i, child: Text(_sections[i]))
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        FocusScope.of(context).unfocus();
                        setState(() => _section = value);
                      }
                    }),
                const SizedBox(height: 12),
                // Replacing sections also disposes text fields/focus state between runs.
                KeyedSubtree(
                    key: ValueKey(_section),
                    child: [
                      _idResolution,
                      _privacy,
                      _dead,
                      _rage,
                      () => _manual(snapshot.data!.autocapture),
                    ][_section]()),
              ]);
            }),
      );
}

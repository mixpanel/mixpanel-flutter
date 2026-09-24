import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/src/autocapture/widget_classification.dart';

void main() {
  test('canonical names and roles do not use text or keys', () {
    const text = Text('secret', key: ValueKey('private'));
    expect(typeName(text), 'Text');
    expect(role(text), 'Text');
    expect(typeName(Semantics(label: 'secret')), 'Semantics');
    expect(typeName(const Placeholder()), 'Widget');
  });
  test('interactivity and dead eligibility remain distinct', () {
    final enabled =
        ElevatedButton(onPressed: () {}, child: const Text('button'));
    const disabled = ElevatedButton(onPressed: null, child: Text('button'));
    expect(isTarget(disabled), isTrue);
    expect(deadEligible(disabled), isFalse);
    expect(deadEligible(enabled), isTrue);
    const field = TextField();
    expect(isFeedbackControl(field), isTrue);
    expect(deadEligible(field), isFalse);
    expect(deadEligible(const Text('plain')), isFalse);
  });
  test('hidden rules inspect visibility, not labels', () {
    expect(hidden(const Offstage()), isTrue);
    expect(hidden(const Visibility(visible: false, child: Text('x'))), isTrue);
    expect(hidden(const Opacity(opacity: 0, child: Text('x'))), isTrue);
    expect(hidden(const Opacity(opacity: 0.1, child: Text('x'))), isFalse);
  });
}

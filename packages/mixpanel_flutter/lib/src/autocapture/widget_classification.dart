import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

bool hidden(Widget w) =>
    (w is Offstage && w.offstage) ||
    (w is Visibility && !w.visible) ||
    (w is Opacity && w.opacity <= 0);

bool hasTap(GestureDetector w) =>
    w.onTap != null || w.onTapUp != null || w.onTapDown != null;
bool isButton(Widget w) =>
    w is ButtonStyleButton || w is IconButton || w is CupertinoButton;
bool isTarget(Widget w) =>
    isButton(w) ||
    isFeedbackControl(w) ||
    w is InkResponse ||
    (w is GestureDetector && hasTap(w));
bool isFeedbackControl(Widget w) =>
    w is EditableText ||
    w is TextField ||
    w is CupertinoTextField ||
    w is Switch ||
    w is CupertinoSwitch ||
    w is Checkbox ||
    w is Radio ||
    w is Slider ||
    w is RangeSlider ||
    w is CupertinoSlider ||
    w is CupertinoPicker ||
    w is CupertinoDatePicker ||
    w is DropdownButton ||
    w is CheckboxListTile ||
    w is SwitchListTile ||
    w is RadioListTile;

bool deadEligible(Widget w) {
  if (isFeedbackControl(w)) return false;
  if (w is ButtonStyleButton) return w.onPressed != null;
  if (w is IconButton) return w.onPressed != null;
  if (w is CupertinoButton) return w.onPressed != null;
  if (w is InkResponse) return w.onTap != null;
  if (w is GestureDetector) return w.onTap != null || w.onTapUp != null;
  return false;
}

String? role(Widget w) {
  if (isButton(w) || w is InkResponse || w is GestureDetector) {
    return 'Button';
  }
  if (w is EditableText || w is TextField || w is CupertinoTextField) {
    return 'TextField';
  }
  if (w is Switch || w is CupertinoSwitch || w is SwitchListTile) {
    return 'Switch';
  }
  if (w is Checkbox || w is CheckboxListTile) return 'Checkbox';
  if (w is Radio || w is RadioListTile) return 'Radio';
  if (w is Slider || w is CupertinoSlider || w is RangeSlider) {
    return 'Slider';
  }
  if (w is Text || w is RichText) return 'Text';
  if (w is Image || w is Icon) return 'Image';
  return null;
}

/// Canonical names survive obfuscation and never stringify arbitrary widgets.
String typeName(Widget w) {
  if (w is ElevatedButton) return 'ElevatedButton';
  if (w is TextButton) return 'TextButton';
  if (w is OutlinedButton) return 'OutlinedButton';
  if (w is FilledButton) return 'FilledButton';
  if (w is IconButton) return 'IconButton';
  if (w is CupertinoButton) return 'CupertinoButton';
  if (w is InkWell) return 'InkWell';
  if (w is InkResponse) return 'InkResponse';
  if (w is GestureDetector) return 'GestureDetector';
  if (w is Semantics) return 'Semantics';
  if (w is Text) return 'Text';
  if (w is RichText) return 'RichText';
  if (w is Icon) return 'Icon';
  if (w is Image) return 'Image';
  if (w is Row) return 'Row';
  if (w is Column) return 'Column';
  if (w is Stack) return 'Stack';
  if (w is Padding) return 'Padding';
  if (w is Container) return 'Container';
  if (w is SizedBox) return 'SizedBox';
  if (w is Scaffold) return 'Scaffold';
  if (isFeedbackControl(w)) return role(w) ?? 'Picker';
  return 'Widget';
}

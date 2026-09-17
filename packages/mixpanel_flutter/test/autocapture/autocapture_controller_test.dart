import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/src/autocapture/autocapture_controller.dart';
import 'package:mixpanel_flutter/src/autocapture/autocapture_options.dart';

void main() {
  late AutocaptureController controller;
  setUp(() => controller =
      AutocaptureController(const AutocaptureOptions(), (_, __) async {}));
  test('navigation during native operation does not invalidate consent epoch',
      () async {
    final epoch = controller.suspend();
    controller.invalidate();
    await controller.refreshConsent(() async => false, consentEpoch: epoch);
    expect(controller.allowed, isTrue);
  });
  test('navigation during consent read permits completion', () async {
    final read = Completer<bool?>();
    final pending = controller.refreshConsent(() => read.future);
    controller.invalidate();
    read.complete(false);
    await pending;
    expect(controller.allowed, isTrue);
  });
  test('newer opt-out defeats an older consent read', () async {
    final read = Completer<bool?>();
    final pending = controller.refreshConsent(() => read.future);
    controller.suspend();
    controller.invalidate();
    read.complete(false);
    await pending;
    expect(controller.allowed, isFalse);
  });
  test('stale native completion never starts a consent read', () async {
    final epoch = controller.suspend();
    controller.suspend();
    var reads = 0;
    await controller.refreshConsent(() async {
      reads++;
      return false;
    }, consentEpoch: epoch);
    expect(reads, 0);
    expect(controller.allowed, isFalse);
  });
  test('close defeats a pending consent read', () async {
    final read = Completer<bool?>();
    final pending = controller.refreshConsent(() => read.future);
    controller.close();
    read.complete(false);
    await pending;
    expect(controller.allowed, isFalse);
  });
}

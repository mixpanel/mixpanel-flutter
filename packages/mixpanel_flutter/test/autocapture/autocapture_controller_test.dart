import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/src/autocapture/autocapture_controller.dart';
import 'package:mixpanel_flutter/src/autocapture/autocapture_options.dart';
import 'package:mixpanel_flutter/src/autocapture/click_event.dart';

void main() {
  late AutocaptureController controller;
  setUp(() => controller =
      AutocaptureController(const AutocaptureOptions(), (_, __) async {}));
  test('navigation during native operation does not invalidate consent request',
      () async {
    final request = controller.beginConsentOperation();
    controller.invalidate();
    await controller.refreshConsent(() async => false, request: request);
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
    final request = controller.beginConsentOperation();
    controller.suspend();
    var reads = 0;
    await controller.refreshConsent(() async {
      reads++;
      return false;
    }, request: request);
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
  test('status has explicit suspended enabled and terminal closed transitions',
      () async {
    expect(controller.status, CaptureStatus.suspended);
    await controller.refreshConsent(() async => false);
    expect(controller.status, CaptureStatus.enabled);
    controller.suspend();
    expect(controller.status, CaptureStatus.suspended);
    controller.close();
    final request = controller.beginConsentOperation();
    var reads = 0;
    await controller.refreshConsent(() async {
      reads++;
      return false;
    }, request: request);
    expect(controller.status, CaptureStatus.closed);
    expect(reads, 0);
    expect(controller.claim(0, Object()), isFalse);
  });

  test('consent request is consumed once and cannot be reused', () async {
    final request = controller.beginConsentOperation();
    var reads = 0;
    Future<bool?> read() async {
      reads++;
      return false;
    }

    await controller.refreshConsent(read, request: request);
    await controller.refreshConsent(read, request: request);
    expect(reads, 1);
    expect(controller.allowed, isTrue);
  });

  test('navigation cancels old session without revoking consent', () async {
    final events = <String>[];
    controller =
        AutocaptureController(const AutocaptureOptions(), (name, _) async {
      events.add(name);
    });
    await controller.refreshConsent(() async => false);
    final old = controller.session;
    controller.invalidate();
    expect(old.isActive, isFalse);
    expect(controller.allowed, isTrue);
    const event = ClickEvent(x: 0, y: 0, elementId: 'target');
    controller.emit('old', event, old);
    controller.emit('current', event, controller.session);
    final other =
        AutocaptureController(const AutocaptureOptions(), (_, __) async {});
    controller.emit('foreign', event, other.session);
    expect(events, ['current']);
    final current = controller.session;
    controller.close();
    expect(current.isActive, isFalse);
    controller.emit('closed', event, current);
    expect(events, ['current']);
  });

  test('close during suspension notification prevents the read from starting',
      () async {
    controller.addListener(() {
      if (controller.status != CaptureStatus.closed) controller.close();
    });
    var reads = 0;
    await controller.refreshConsent(() async {
      reads++;
      return false;
    });
    expect(reads, 0);
    expect(controller.status, CaptureStatus.closed);
  });
}

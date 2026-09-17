import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/codec/mixpanel_message_codec.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(
      'mixpanel_flutter', StandardMethodCodec(MixpanelMessageCodec()));
  final events = <String>[];
  Future<Object?> Function(MethodCall)? intercept;
  bool optedOut = false;

  setUp(() {
    events.clear();
    intercept = null;
    optedOut = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'track') {
        events.add((call.arguments as Map)['eventName'] as String);
        return null;
      }
      if (call.method == 'optOutTracking') {
        optedOut = true;
        return null;
      }
      if (intercept != null) return intercept!(call);
      if (call.method == 'hasOptedOutTracking') return optedOut;
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  Future<Mixpanel> init() => Mixpanel.init('test',
      trackAutomaticEvents: false,
      autocaptureOptions: const AutocaptureOptions());
  Widget host(Mixpanel instance) => MixpanelAutocaptureWidget(
      instance: instance,
      child: MaterialApp(
          home: Scaffold(
              body: Center(
                  child: ElevatedButton(
                      onPressed: () {}, child: const Text('Tap'))))));
  Future<void> invoke(Mixpanel instance, String operation) =>
      operation == 'identify'
          ? instance.identify('new-user')
          : instance.reset();
  Matcher getOriginalError() => isA<PlatformException>()
      .having((error) => error.code, 'code', 'native_failure')
      .having((error) => error.message, 'message', 'original error');

  for (final operation in ['identify', 'reset']) {
    for (final consent in ['allowed', 'denied', 'unknown', 'failure']) {
      testWidgets(
          '$operation failure recovers only with confirmed consent: $consent',
          (tester) async {
        final instance = await init();
        await tester.pumpWidget(host(instance));
        await tester.tap(find.text('Tap'));
        await tester.pump();
        intercept = (call) async {
          if (call.method == operation) {
            throw PlatformException(
                code: 'native_failure', message: 'original error');
          }
          if (call.method == 'hasOptedOutTracking') {
            if (consent == 'failure') {
              throw PlatformException(code: 'consent_failure');
            }
            return consent == 'unknown' ? null : consent != 'allowed';
          }
          return null;
        };
        await expectLater(
            invoke(instance, operation), throwsA(getOriginalError()));
        events.clear();
        await tester.pump(const Duration(milliseconds: 501));
        expect(events, isEmpty,
            reason: 'the pre-operation dead candidate stays cancelled');
        await tester.tap(find.text('Tap'));
        await tester.pump(const Duration(milliseconds: 501));
        expect(events,
            consent == 'allowed' ? [r'$mp_click', r'$mp_dead_click'] : isEmpty);
      });
    }

    for (final duringConsent in [false, true]) {
      testWidgets(
          '$operation failure recovery cannot override opt-out during ${duringConsent ? 'consent read' : 'native operation'}',
          (tester) async {
        final instance = await init();
        await tester.pumpWidget(host(instance));
        final gate = Completer<void>();
        var consentReads = 0;
        intercept = (call) async {
          if (call.method == operation) {
            if (!duringConsent) await gate.future;
            throw PlatformException(
                code: 'native_failure', message: 'original error');
          }
          if (call.method == 'hasOptedOutTracking') {
            consentReads++;
            if (duringConsent) await gate.future;
            // Deliberately stale result; the newer opt-out must still win.
            return false;
          }
          return null;
        };
        final pending = expectLater(
            invoke(instance, operation), throwsA(getOriginalError()));
        await tester.pump();
        instance.optOutTracking();
        await tester.pump();
        gate.complete();
        await pending;
        await tester.tap(find.text('Tap'));
        await tester.pump(const Duration(milliseconds: 501));
        expect(events, isEmpty);
        expect(consentReads, duringConsent ? 1 : 0);
      });
    }

    testWidgets(
        '$operation failure cannot resume before a newer reset completes',
        (tester) async {
      final instance = await init();
      await tester.pumpWidget(host(instance));
      final oldGate = Completer<void>();
      final resetGate = Completer<void>();
      var first = true;
      var reads = 0;
      intercept = (call) async {
        if (first && call.method == operation) {
          first = false;
          await oldGate.future;
          throw PlatformException(
              code: 'native_failure', message: 'original error');
        }
        if (call.method == 'reset') await resetGate.future;
        if (call.method == 'hasOptedOutTracking') {
          reads++;
          return false;
        }
        return null;
      };
      final failed =
          expectLater(invoke(instance, operation), throwsA(getOriginalError()));
      await tester.pump();
      final newer = instance.reset();
      await tester.pump();
      oldGate.complete();
      await failed;
      await tester.tap(find.text('Tap'));
      await tester.pump();
      expect(events, isEmpty);
      expect(reads, 0);
      resetGate.complete();
      await newer;
      await tester.tap(find.text('Tap'));
      await tester.pump(const Duration(milliseconds: 501));
      expect(events, [r'$mp_click', r'$mp_dead_click']);
      expect(reads, 1);
    });

    testWidgets(
        '$operation late failure cannot revive capture after reinitialization',
        (tester) async {
      final instance = await init();
      await tester.pumpWidget(host(instance));
      final gate = Completer<void>();
      var recoveryReads = 0;
      intercept = (call) async {
        if (call.method == operation) {
          await gate.future;
          throw PlatformException(
              code: 'native_failure', message: 'original error');
        }
        if (call.method == 'hasOptedOutTracking') {
          recoveryReads++;
          return false;
        }
        return null;
      };
      final pending =
          expectLater(invoke(instance, operation), throwsA(getOriginalError()));
      await tester.pump();
      // Reinitialize with automatic capture disabled, leaving the old widget
      // mounted to prove its closed controller cannot be re-enabled.
      await Mixpanel.init('replacement', trackAutomaticEvents: false);
      gate.complete();
      await pending;
      await tester.tap(find.text('Tap'));
      await tester.pump(const Duration(milliseconds: 501));
      expect(events, isEmpty);
      expect(recoveryReads, 0);
    });
  }
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/codec/mixpanel_message_codec.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(
      'mixpanel_flutter', StandardMethodCodec(MixpanelMessageCodec()));
  final calls = <MethodCall>[];
  late Mixpanel mixpanel;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    mixpanel = await Mixpanel.init('test', trackAutomaticEvents: false);
    calls.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final kind in ['click', 'rage_click', 'dead_click']) {
    Future<void> emit(ClickEvent event, {Map<String, dynamic>? properties}) {
      switch (kind) {
        case 'rage_click':
          return mixpanel.autocapture
              .trackRageClick(event, properties: properties);
        case 'dead_click':
          return mixpanel.autocapture
              .trackDeadClick(event, properties: properties);
        default:
          return mixpanel.autocapture.trackClick(event, properties: properties);
      }
    }

    test('$kind sends one normalized event and protects typed metadata',
        () async {
      final properties = <String, dynamic>{
        'custom': 'value',
        r'$mp_autocapture': false,
        r'$x': 900,
        r'$el_id': 'wrong',
        r'$el_tag_name': 'wrong',
        r'$attr-role': 'wrong',
        r'$elements': 'wrong',
      };
      await emit(
        const ClickEvent(
            x: 12.9,
            y: -2.9,
            elementId: 'checkout',
            tagName: 'ElevatedButton',
            role: 'Button',
            elements: 'ElevatedButton > Column'),
        properties: properties,
      );
      expect(calls, hasLength(1));
      expect(
          calls.single,
          isMethodCall('track', arguments: {
            'eventName': '\$mp_$kind',
            'properties': {
              'custom': 'value',
              r'$mp_autocapture': true,
              r'$x': 12,
              r'$y': -2,
              r'$el_id': 'checkout',
              r'$el_tag_name': 'ElevatedButton',
              r'$attr-role': 'Button',
              r'$elements': 'ElevatedButton > Column',
            },
          }));
      expect(properties[r'$el_id'], 'wrong');
    });

    test('$kind rejects blank IDs and nonfinite coordinates', () async {
      for (final id in ['', '  ', '\n\t']) {
        await emit(ClickEvent(x: 0, y: 0, elementId: id));
      }
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity
      ]) {
        await emit(ClickEvent(x: value, y: 0, elementId: 'target'));
        await emit(ClickEvent(x: 0, y: value, elementId: 'target'));
      }
      expect(calls, isEmpty);
    });

    test('$kind omits absent optional metadata and does not infer labels',
        () async {
      await emit(const ClickEvent(x: 0, y: 0, elementId: 'target', role: ' '),
          properties: {
            r'$el_tag_name': 'wrong',
            r'$attr-role': 'wrong',
            r'$elements': 'wrong'
          });
      expect(calls.single.arguments['properties'], {
        r'$x': 0,
        r'$y': 0,
        r'$el_id': 'target',
        r'$mp_autocapture': true,
      });
    });

    test('$kind contains platform errors', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(
            code: 'unavailable', message: 'private payload');
      });
      await expectLater(
          emit(const ClickEvent(x: 0, y: 0, elementId: 'target')), completes);
    });
  }
}

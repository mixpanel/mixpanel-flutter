import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/native_image_compressor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.mixpanel.flutter_session_replay');
  final rgba = Uint8List(4 * 4 * 4);

  void mockCompressImage(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('NativeImageCompressor', () {
    test('returns the platform encoder output', () async {
      // GIVEN a platform encoder that answers
      final encoded = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]);
      mockCompressImage((call) async {
        expect(call.method, 'compressImage');
        return encoded;
      });

      // WHEN
      final result = await NativeImageCompressor().compress(
        rgba,
        width: 4,
        height: 4,
      );

      // THEN
      expect(result, encoded);
    });

    test('drops the frame when the platform encoder fails', () async {
      // GIVEN a channel that has no native handler, as in a host where the
      // plugin is not registered
      mockCompressImage((call) async {
        throw MissingPluginException('no implementation');
      });

      // WHEN / THEN there is no slow Dart fallback; the frame is dropped
      final result = await NativeImageCompressor().compress(
        rgba,
        width: 4,
        height: 4,
      );
      expect(result, isNull);
    });

    test('drops the frame when the platform encoder returns nothing', () async {
      mockCompressImage((call) async => null);

      final result = await NativeImageCompressor().compress(
        rgba,
        width: 4,
        height: 4,
      );

      expect(result, isNull);
    });
  });
}

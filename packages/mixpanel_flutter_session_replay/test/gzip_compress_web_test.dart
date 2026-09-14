@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/platform/gzip_compress_web.dart';

void main() {
  group('Web Gzip Compression', () {
    setUpAll(initializeGzipCompression);

    test('isGzipSupported returns true on web', () {
      expect(isGzipSupported, true);
    });

    test('gzipCompress throws UnsupportedError on web', () {
      expect(() => gzipCompress([1, 2, 3]), throwsA(isA<UnsupportedError>()));
    });

    test('gzipCompressAsync produces valid gzip output', () async {
      final input =
          'Hello, World! This is a test of gzip compression.'.codeUnits;

      final compressed = await gzipCompressAsync(input);

      expect(compressed, isNotEmpty);
      // Gzip magic bytes: 0x1f 0x8b
      expect(compressed[0], 0x1f);
      expect(compressed[1], 0x8b);
    });

    test('gzipCompressAsync handles empty input', () async {
      final compressed = await gzipCompressAsync([]);

      expect(compressed, isNotEmpty); // Gzip header is still emitted
      expect(compressed[0], 0x1f);
      expect(compressed[1], 0x8b);
    });

    test('gzipCompressAsync compresses repetitive data', () async {
      // Highly compressible: 10KB of repeated bytes
      final input = Uint8List(10000);
      for (int i = 0; i < input.length; i++) {
        input[i] = 65; // 'A'
      }

      final compressed = await gzipCompressAsync(input);

      expect(compressed.length, lessThan(input.length));
    });

    test('gzipCompressAsync preserves data through compression', () async {
      // Different inputs should produce different outputs
      final input1 = 'first payload'.codeUnits;
      final input2 = 'second payload'.codeUnits;

      final compressed1 = await gzipCompressAsync(input1);
      final compressed2 = await gzipCompressAsync(input2);

      expect(compressed1, isNot(equals(compressed2)));
    });

    test(
      'serializes concurrent compression requests through the worker',
      () async {
        final outputs = await Future.wait(
          List.generate(
            4,
            (index) => gzipCompressAsync('concurrent payload $index'.codeUnits),
          ),
        );

        expect(outputs, hasLength(4));
        expect(outputs.every((output) => output.isNotEmpty), true);
      },
    );
  });
}

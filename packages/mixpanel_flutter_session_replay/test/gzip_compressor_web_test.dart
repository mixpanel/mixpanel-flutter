@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/platform/gzip_compressor_web.dart';

void main() {
  group('WebGzipCompressor', () {
    late WebGzipCompressor compressor;

    setUp(() async {
      compressor = WebGzipCompressor();
      await compressor.initialize();
    });

    tearDown(() => compressor.dispose());

    test('reports CompressionStream support', () {
      expect(compressor.isSupported, isTrue);
    });

    test('produces valid gzip output', () async {
      final compressed = await compressor.compress(
        'Hello, World! This is a test of gzip compression.'.codeUnits,
      );

      expect(compressed.take(2), [0x1f, 0x8b]);
    });

    test('handles empty input', () async {
      final compressed = await compressor.compress([]);

      expect(compressed.take(2), [0x1f, 0x8b]);
    });

    test('compresses repetitive data', () async {
      final input = Uint8List(10000)..fillRange(0, 10000, 65);

      final compressed = await compressor.compress(input);

      expect(compressed.length, lessThan(input.length));
    });

    test('different inputs produce different output', () async {
      final first = await compressor.compress('first payload'.codeUnits);
      final second = await compressor.compress('second payload'.codeUnits);

      expect(first, isNot(equals(second)));
    });

    test('serializes concurrent requests through one worker', () async {
      final outputs = await Future.wait(
        List.generate(
          4,
          (index) => compressor.compress('concurrent payload $index'.codeUnits),
        ),
      );

      expect(outputs, hasLength(4));
      expect(outputs.every((output) => output.isNotEmpty), isTrue);
    });

    test('disposing one instance leaves another instance intact', () async {
      // GIVEN a request queued on an instance that is then disposed, as when
      // an SDK instance is replaced, while a new instance initializes
      final replacement = WebGzipCompressor();
      addTearDown(replacement.dispose);
      final pending = compressor.compress('pending payload'.codeUnits);
      final staleFailure = expectLater(
        pending,
        throwsA(isA<UnsupportedError>()),
      );
      compressor.dispose();

      // WHEN
      await replacement.initialize();
      await staleFailure;

      // THEN the replacement serves uploads; the stale failure touched only
      // the disposed instance's worker
      final compressed = await replacement.compress('after replace'.codeUnits);
      expect(compressed.take(2), [0x1f, 0x8b]);
    });

    test('rejects use after dispose', () async {
      compressor.dispose();

      expect(() => compressor.compress([1, 2, 3]), throwsStateError);
      expect(compressor.initialize, throwsStateError);
    });
  });
}

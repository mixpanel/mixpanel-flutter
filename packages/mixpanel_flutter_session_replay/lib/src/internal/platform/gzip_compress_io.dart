import 'dart:io' show gzip;

bool get isGzipSupported => true;

Future<void> initializeGzipCompression() async {}

void disposeGzipCompression() {}

List<int> gzipCompress(List<int> bytes) => gzip.encode(bytes);

Future<List<int>> gzipCompressAsync(List<int> bytes) async =>
    gzip.encode(bytes);

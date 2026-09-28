bool get isGzipSupported => false;

Future<void> initializeGzipCompression() async {}

void disposeGzipCompression() {}

List<int> gzipCompress(List<int> bytes) => bytes;

Future<List<int>> gzipCompressAsync(List<int> bytes) async => bytes;

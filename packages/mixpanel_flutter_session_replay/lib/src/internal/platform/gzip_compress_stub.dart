bool get isGzipSupported => false;

Future<void> initializeGzipCompression() async {}

List<int> gzipCompress(List<int> bytes) => bytes;

Future<List<int>> gzipCompressAsync(List<int> bytes) async => bytes;

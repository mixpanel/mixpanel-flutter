export 'gzip_compressor_stub.dart'
    if (dart.library.io) 'gzip_compressor_io.dart'
    if (dart.library.js_interop) 'gzip_compressor_web.dart';

export 'gzip_compress_stub.dart'
    if (dart.library.io) 'gzip_compress_io.dart'
    if (dart.library.js_interop) 'gzip_compress_web.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

const _port = 8765;

Future<void> main(List<String> args) async {
  var uploadCount = 0;
  var artifactCount = 0;
  var recoverableUploadCount = 0;
  Object? validationError;
  final standalone = args.contains('--standalone');
  final validationComplete = Completer<void>();
  final artifactDirectory = Directory('build/web_motion_mask_validation');
  await artifactDirectory.create(recursive: true);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
  server.listen((request) async {
    request.response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'POST, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Authorization, Content-Type');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    try {
      if (request.method == 'POST' &&
          request.uri.pathSegments.length == 2 &&
          request.uri.pathSegments.first == 'artifact') {
        final name = request.uri.pathSegments.last;
        if (!RegExp(r'^[a-z0-9_.-]+$').hasMatch(name)) {
          throw StateError('Invalid artifact name: $name');
        }
        final body = await request.fold<List<int>>(
          <int>[],
          (bytes, chunk) => bytes..addAll(chunk),
        );
        await File('${artifactDirectory.path}/$name').writeAsBytes(body);
        artifactCount++;
        if (standalone && name == 'performance.json') {
          validationComplete.complete();
        }
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        return;
      }
      final isNormalUpload = request.uri.path == '/record';
      final isRecoverableUpload = request.uri.path == '/recoverable/record';
      if (request.method != 'POST' ||
          (!isNormalUpload && !isRecoverableUpload)) {
        throw StateError(
          'Unexpected request: ${request.method} ${request.uri}',
        );
      }
      final body = await request.fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
      if (body.length < 2 || body[0] != 0x1f || body[1] != 0x8b) {
        throw StateError('Upload body is not gzip encoded');
      }
      final decoded = jsonDecode(utf8.decode(gzip.decode(body)));
      if (decoded is! List || decoded.length < 2) {
        if (!isRecoverableUpload || decoded is! List || decoded.isEmpty) {
          throw StateError('Upload did not contain the expected events');
        }
      }
      if (isRecoverableUpload &&
          !decoded.whereType<Map<String, dynamic>>().any(
            (event) =>
                event['data'] is Map<String, dynamic> &&
                (event['data'] as Map<String, dynamic>)['type'] == 2,
          )) {
        throw StateError('Recovery upload omitted the rrweb click event');
      }
      if (request.headers.value(HttpHeaders.authorizationHeader) == null) {
        throw StateError('Upload omitted the authorization header');
      }
      if (isRecoverableUpload) {
        recoverableUploadCount++;
        if (recoverableUploadCount == 1) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
      }
      uploadCount++;
      request.response.statusCode = HttpStatus.ok;
    } catch (error) {
      validationError = error;
      stderr.writeln(
        'Validation request failed for ${request.uri.path}: $error',
      );
      request.response.statusCode = HttpStatus.badRequest;
    }
    await request.response.close();
  });

  if (standalone) {
    stdout.writeln(
      'Web validation receiver listening on http://127.0.0.1:$_port',
    );
    await validationComplete.future.timeout(const Duration(minutes: 5));
    await server.close(force: true);
    if (validationError case final error?) throw error;
    if (uploadCount != 2 || recoverableUploadCount != 2) {
      throw StateError(
        'Expected one normal upload and a failed/successful recovery pair; '
        'received $uploadCount successful uploads and '
        '$recoverableUploadCount recovery attempts',
      );
    }
    stdout.writeln('Wrote $artifactCount web validation artifacts');
    return;
  }

  await integrationDriver(
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      await server.close(force: true);
      await writeResponseData(data);
      if (validationError case final error?) throw error;
      if (uploadCount != 2 || recoverableUploadCount != 2) {
        throw StateError(
          'Expected one normal upload and a failed/successful recovery pair; '
          'received $uploadCount successful uploads and '
          '$recoverableUploadCount recovery attempts',
        );
      }
      stdout.writeln('Wrote $artifactCount motion validation artifacts');
    },
  );
}

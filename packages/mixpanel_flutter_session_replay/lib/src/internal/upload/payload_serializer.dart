import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';

import '../../models/session_event.dart';
import '../../models/session.dart';
import '../../version.dart';
import 'rrweb_event.dart';

/// Result of payload serialization
class SerializedPayload {
  /// The serialized body data (JSON string or compressed bytes)
  final dynamic body;

  /// HTTP headers to send with the request
  final Map<String, String> headers;

  /// Whether the body is compressed
  final bool isCompressed;

  SerializedPayload({
    required this.body,
    required this.headers,
    required this.isCompressed,
  });
}

/// Payload serializer for session replay events
///
/// Serializes events as GZIP compressed bytes.
/// Uses format=gzip query parameter to indicate compression.
class PayloadSerializer {
  final String _token;

  PayloadSerializer(this._token);

  Future<SerializedPayload> serialize(
    List<SessionReplayEvent> events,
    Session session,
    String distinctId,
    int sequenceNumber,
  ) async {
    if (events.isEmpty) {
      final compressed = await _gzipCompress(jsonEncode([]));
      return SerializedPayload(
        body: compressed,
        headers: {
          'Authorization': buildAuthHeader(_token),
          'Content-Type': 'application/octet-stream',
        },
        isCompressed: true,
      );
    }

    final result = <Map<String, dynamic>>[];

    // Add all events (converted to rrweb format)
    // MetadataPayload events are automatically converted to RRWeb Meta events
    result.addAll(
      events.map((e) => RRWebEvent.fromSessionReplayEvent(e).toJson()).toList(),
    );

    // Create JSON string
    final jsonString = jsonEncode(result);

    // GZIP compress the payload
    final compressed = await _gzipCompress(jsonString);

    return SerializedPayload(
      body: compressed,
      headers: {
        'Authorization': buildAuthHeader(_token),
        'Content-Type': 'application/octet-stream',
      },
      isCompressed: true,
    );
  }

  String buildAuthHeader(String token) {
    final credentials = base64Encode(utf8.encode('$token:'));
    return 'Basic $credentials';
  }

  Map<String, String> buildQueryParams(
    Session session,
    String distinctId,
    int sequenceNumber,
  ) {
    final batchStartTime = clock.now().millisecondsSinceEpoch / 1000.0;
    final replayLength = clock
        .now()
        .difference(session.startTime)
        .inMilliseconds;
    final replayStartTime = session.startTime.millisecondsSinceEpoch / 1000.0;

    return {
      'format': 'gzip', // Indicate compression via query param (not header)
      'distinct_id': distinctId,
      'seq': sequenceNumber.toString(),
      'batch_start_time': batchStartTime.toString(),
      'replay_id': session.id,
      'replay_length_ms': replayLength.toString(),
      'replay_start_time': replayStartTime.toString(),
      '\$lib_version': sdkVersion,
      '\$os': operatingSystem,
      'mp_lib': 'flutter-sr',
    };
  }

  /// GZIP compress a string
  Future<List<int>> _gzipCompress(String data) async {
    final bytes = utf8.encode(data);
    return gzip.encode(bytes);
  }
}

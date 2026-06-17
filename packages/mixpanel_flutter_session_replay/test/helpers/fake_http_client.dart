import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

/// Creates a MockClient that returns a fixed response for all requests.
///
/// Use this for simple cases where every request should return the same response.
http.Client createFakeHttpClient({
  required int statusCode,
  String body = '',
  Map<String, String> headers = const {},
}) {
  return http_testing.MockClient((request) async {
    return http.Response(body, statusCode, headers: headers);
  });
}

/// Creates a MockClient that returns a settings response.
///
/// [isEnabled] controls whether recording is enabled in the response.
/// [recordSessionsPercent] optionally includes sdk_config with the given value.
http.Client createFakeSettingsClient({
  required bool isEnabled,
  double? recordSessionsPercent,
}) {
  return http_testing.MockClient((request) async {
    final response = <String, dynamic>{
      'recording': {'is_enabled': isEnabled},
    };
    if (recordSessionsPercent != null) {
      response['sdk_config'] = {
        'config': {'record_sessions_percent': recordSessionsPercent},
      };
    }
    return http.Response(jsonEncode(response), 200);
  });
}

/// Creates a MockClient that throws an exception on any request.
http.Client createFailingHttpClient({String errorMessage = 'Network error'}) {
  return http_testing.MockClient((request) async {
    throw Exception(errorMessage);
  });
}

/// Creates a MockClient that records requests for later inspection.
///
/// Returns the client and a list that will be populated with requests.
({http.Client client, List<http.Request> requests}) createRecordingHttpClient({
  required int statusCode,
  String body = '',
}) {
  final requests = <http.Request>[];

  final client = http_testing.MockClient((request) async {
    requests.add(request);
    return http.Response(body, statusCode);
  });

  return (client: client, requests: requests);
}

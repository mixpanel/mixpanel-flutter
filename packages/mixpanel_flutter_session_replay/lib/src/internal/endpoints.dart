import '../models/data_residency.dart';

/// Builds the full `/record` and `/settings` endpoint URLs from a base server
/// URL.
///
/// Mirrors the Android implementation: any path on the base URL is preserved,
/// only a trailing `/` is trimmed before appending the endpoint path. This
/// allows custom base URLs such as `https://proxy.example.com/mp` to resolve
/// to `https://proxy.example.com/mp/record`.
abstract final class EndPoints {
  /// Default base URL used when no override is provided.
  static const String defaultBaseUrl = DataResidency.us;

  /// Build the `/record` endpoint URL for the given base URL.
  static String record(String baseUrl) =>
      '${_trimTrailingSlash(baseUrl)}/record';

  /// Build the `/settings` endpoint URL for the given base URL.
  static String settings(String baseUrl) =>
      '${_trimTrailingSlash(baseUrl)}/settings';

  static String _trimTrailingSlash(String input) {
    var end = input.length;
    while (end > 0 && input.codeUnitAt(end - 1) == 0x2F /* '/' */ ) {
      end--;
    }
    return input.substring(0, end);
  }
}

/// Result of validating a [SessionReplayOptions.serverUrl] value.
///
/// Mirrors Android's `Result<String>` returned from `validateServerUrl`.
sealed class ServerUrlValidation {
  const ServerUrlValidation();
}

/// Validation succeeded; [trimmedUrl] is the canonical value to use.
final class ServerUrlValid extends ServerUrlValidation {
  final String trimmedUrl;
  const ServerUrlValid(this.trimmedUrl);
}

/// Validation failed; [message] explains why.
final class ServerUrlInvalid extends ServerUrlValidation {
  final String message;
  const ServerUrlInvalid(this.message);
}

/// Validate a user-supplied `serverUrl` value.
///
/// Mirrors Android's `SessionReplayManager.validateServerUrl`:
/// - whitespace is trimmed
/// - URL must start with `https://`
/// - URL must parse as a valid absolute URI with a host
///
/// Notably this does NOT reject URLs that include a path — proxy URLs like
/// `https://proxy.example.com/mp` are accepted, and the path is preserved
/// when building the record/settings endpoints. (The iOS implementation
/// rejects such URLs; we intentionally diverge from iOS to match Android.)
ServerUrlValidation validateServerUrl(String url) {
  final trimmed = url.trim();

  if (!trimmed.startsWith('https://')) {
    return ServerUrlInvalid(
      'serverUrl must start with https://, got: "$trimmed"',
    );
  }

  final parsed = Uri.tryParse(trimmed);
  if (parsed == null || !parsed.isAbsolute || parsed.host.isEmpty) {
    return ServerUrlInvalid('serverUrl "$trimmed" is malformed');
  }

  return ServerUrlValid(trimmed);
}

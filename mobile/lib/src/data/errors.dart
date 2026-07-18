/// Stable error taxonomy for identification, mirroring the error codes
/// returned by the Erlang `aircraft_id` facade (`message_for/1`).
enum IdentifyError {
  notConfigured,
  networkUnavailable,
  dnsFailed,
  tlsFailed,
  openskyTimeout,
  openskyRateLimited,
  openskyUnauthorized,
  openskyBadResponse,
}

/// Thrown by the data layer to signal a classified failure.
class IdentifyException implements Exception {
  final IdentifyError code;

  const IdentifyException(this.code);

  @override
  String toString() => 'IdentifyException(${code.name})';
}

/// Human-friendly message for each error code, mirroring the library copy.
String messageForError(IdentifyError code) {
  switch (code) {
    case IdentifyError.notConfigured:
      return 'Set your location to identify aircraft overhead.';
    case IdentifyError.networkUnavailable:
      return 'The network is unavailable.';
    case IdentifyError.dnsFailed:
      return 'Could not resolve the aircraft service host.';
    case IdentifyError.tlsFailed:
      return 'A secure connection to the aircraft service failed.';
    case IdentifyError.openskyTimeout:
      return 'The aircraft service did not respond in time.';
    case IdentifyError.openskyRateLimited:
      return 'The aircraft service is rate limiting requests. Try again shortly.';
    case IdentifyError.openskyUnauthorized:
      return 'The aircraft service rejected the request.';
    case IdentifyError.openskyBadResponse:
      return 'The aircraft service returned an invalid response.';
  }
}

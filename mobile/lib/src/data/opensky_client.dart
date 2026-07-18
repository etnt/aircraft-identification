/// OpenSky provider: request construction, response parsing, and error
/// mapping. A port of the Erlang `aircraft_id_opensky` module.
library;

import 'dart:convert';

import '../config/identify_config.dart';
import '../domain/geo.dart' as geo;
import '../domain/models.dart';
import 'errors.dart';
import 'http.dart';

class OpenSkyClient {
  final HttpTransport _http;

  /// Optional bearer-token source. OpenSky's public `/states/all` endpoint
  /// still serves anonymous requests (heavily rate limited); supplying a
  /// token here upgrades to the authenticated quota. Returns `null` to stay
  /// anonymous. See the auth note in `plans/flutter_app.md`.
  final Future<String?> Function()? _tokenProvider;

  static const int _maxBody = 262144;
  static const Duration _timeout = Duration(milliseconds: 12000);

  const OpenSkyClient(this._http, {Future<String?> Function()? tokenProvider})
      : _tokenProvider = tokenProvider; // ignore: prefer_initializing_formals

  /// Build the bounded `/states/all` URL for the observer config.
  static Uri buildUrl(IdentifyConfig config) {
    final BoundingBox box = geo.boundingBox(
      config.latitude,
      config.longitude,
      config.effectiveRadiusKm,
    );
    return Uri.https('opensky-network.org', '/api/states/all', {
      'lamin': box.south.toStringAsFixed(6),
      'lomin': box.west.toStringAsFixed(6),
      'lamax': box.north.toStringAsFixed(6),
      'lomax': box.east.toStringAsFixed(6),
      'extended': '1',
    });
  }

  /// Extract the list of raw state vectors from a decoded response.
  static List<dynamic> parseStates(Object? decoded) {
    if (decoded is Map && decoded['states'] is List) {
      return decoded['states'] as List<dynamic>;
    }
    return const [];
  }

  /// Perform exactly one OpenSky state query.
  ///
  /// Returns the raw `states` list, or throws [IdentifyException] with a
  /// stable [IdentifyError] on any provider or transport failure.
  Future<List<dynamic>> fetchStates(IdentifyConfig config) async {
    final headers = <String, String>{
      'accept': 'application/json',
      'accept-encoding': 'identity',
      'connection': 'close',
    };
    final token = await _tokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      headers['authorization'] = 'Bearer $token';
    }

    final HttpResponse response;
    try {
      response = await _http.get(
        buildUrl(config),
        headers: headers,
        timeout: _timeout,
        maxBody: _maxBody,
      );
    } on TransportException catch (e) {
      throw IdentifyException(_classifyTransport(e.kind));
    }

    switch (response.status) {
      case 200:
        try {
          return parseStates(jsonDecode(response.body));
        } on FormatException {
          throw const IdentifyException(IdentifyError.openskyBadResponse);
        }
      case 401:
      case 403:
        throw const IdentifyException(IdentifyError.openskyUnauthorized);
      case 429:
        throw const IdentifyException(IdentifyError.openskyRateLimited);
      default:
        throw const IdentifyException(IdentifyError.openskyBadResponse);
    }
  }

  static IdentifyError _classifyTransport(TransportErrorKind kind) {
    switch (kind) {
      case TransportErrorKind.timeout:
        return IdentifyError.openskyTimeout;
      case TransportErrorKind.dnsFailed:
        return IdentifyError.dnsFailed;
      case TransportErrorKind.tlsFailed:
        return IdentifyError.tlsFailed;
      case TransportErrorKind.tooLarge:
        return IdentifyError.openskyBadResponse;
      case TransportErrorKind.connectionFailed:
      case TransportErrorKind.other:
        return IdentifyError.networkUnavailable;
    }
  }
}

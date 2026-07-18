/// ADSBDB enrichment for the selected candidate. A port of the Erlang
/// `aircraft_id_adsbdb` module.
///
/// The response field mapping was verified against the live API on
/// 2026-07-18 (icao24 `3c6745` / callsign `DLH804` -> registration
/// `D-AIZE`, an Airbus A320, full FRA->ARN route).
///
/// Enrichment is best effort: any failure (non-200, timeout, malformed
/// body) returns the positional candidate unchanged with
/// `enrichmentStatus = unavailable`, never discarding a valid result.
library;

import 'dart:convert';

import '../domain/models.dart';
import 'http.dart';

class AdsbdbClient {
  final HttpTransport _http;

  static const int _maxBody = 32768;
  static const Duration _timeout = Duration(milliseconds: 8000);

  const AdsbdbClient(this._http);

  /// Combined aircraft (+ optional callsign route) endpoint URL.
  static Uri buildUrl(String icao, String? callsign) {
    return Uri.https(
      'api.adsbdb.com',
      '/v0/aircraft/$icao',
      (callsign != null && callsign.isNotEmpty) ? {'callsign': callsign} : null,
    );
  }

  /// Enrich the primary candidate. Returns the candidate either way.
  Future<Candidate> enrich(Candidate candidate) async {
    try {
      final response = await _http.get(
        buildUrl(candidate.icao24, candidate.callsign),
        headers: const {
          'accept': 'application/json',
          'accept-encoding': 'identity',
          'connection': 'close',
        },
        timeout: _timeout,
        maxBody: _maxBody,
      );
      if (response.status != 200) {
        return candidate.copyWith(enrichmentStatus: EnrichmentStatus.unavailable);
      }
      final decoded = jsonDecode(response.body);
      return _apply(candidate, parse(decoded));
    } catch (_) {
      return candidate.copyWith(enrichmentStatus: EnrichmentStatus.unavailable);
    }
  }

  /// Map a decoded ADSBDB response into candidate override fields.
  static AdsbdbFields parse(Object? decoded) {
    if (decoded is! Map || decoded['response'] is! Map) {
      return const AdsbdbFields();
    }
    final response = decoded['response'] as Map;
    final aircraft = _map(response['aircraft']);
    final route = _map(response['flightroute']);
    final airlineName = _str(_map(route['airline'])['name']);
    return AdsbdbFields(
      registration: _str(aircraft['registration']),
      manufacturer: _str(aircraft['manufacturer']),
      model: _str(aircraft['type']),
      registeredOwnerOperator: _str(aircraft['registered_owner']),
      photoUrl: _str(aircraft['url_photo']),
      airline: airlineName,
      origin: _airport(_map(route['origin'])),
      destination: _airport(_map(route['destination'])),
    );
  }

  static Candidate _apply(Candidate candidate, AdsbdbFields fields) {
    return candidate.copyWith(
      registration: fields.registration,
      manufacturer: fields.manufacturer,
      model: fields.model,
      registeredOwnerOperator: fields.registeredOwnerOperator,
      photoUrl: fields.photoUrl,
      airline: fields.airline,
      origin: fields.origin,
      destination: fields.destination,
      enrichmentStatus: EnrichmentStatus.ok,
    );
  }

  static Airport? _airport(Map<dynamic, dynamic> map) {
    if (map.isEmpty) return null;
    final airport = Airport(
      icao: _str(map['icao_code']),
      iata: _str(map['iata_code']),
      name: _str(map['name']),
    );
    if (airport.icao == null && airport.iata == null && airport.name == null) {
      return null;
    }
    return airport;
  }

  static Map<dynamic, dynamic> _map(Object? v) => v is Map ? v : const {};

  static String? _str(Object? v) =>
      v is String && v.isNotEmpty ? v : null;
}

/// The subset of fields ADSBDB can contribute to a candidate.
class AdsbdbFields {
  final String? registration;
  final String? manufacturer;
  final String? model;
  final String? registeredOwnerOperator;
  final String? photoUrl;
  final String? airline;
  final Airport? origin;
  final Airport? destination;

  const AdsbdbFields({
    this.registration,
    this.manufacturer,
    this.model,
    this.registeredOwnerOperator,
    this.photoUrl,
    this.airline,
    this.origin,
    this.destination,
  });
}

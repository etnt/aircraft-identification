import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:skyoverhead/src/config/identify_config.dart';
import 'package:skyoverhead/src/data/adsbdb_client.dart';
import 'package:skyoverhead/src/data/aircraft_service.dart';
import 'package:skyoverhead/src/data/errors.dart';
import 'package:skyoverhead/src/data/http.dart';
import 'package:skyoverhead/src/data/opensky_client.dart';
import 'package:skyoverhead/src/domain/models.dart';

import 'support/fake_transport.dart';

const _now = 1000000;
const _config = IdentifyConfig(latitude: 59.3, longitude: 18.0);

DateTime _clock() =>
    DateTime.fromMillisecondsSinceEpoch(_now * 1000, isUtc: true);

/// Build an OpenSky-style extended state vector (18 elements).
List<dynamic> _vec({
  required String icao,
  String callsign = 'TEST',
  required double lat,
  required double lon,
  double geoAlt = 10000.0,
  int timePos = _now,
  bool onGround = false,
}) {
  return <dynamic>[
    icao,
    callsign,
    'Testland',
    timePos,
    timePos,
    lon,
    lat,
    geoAlt - 50,
    onGround,
    100.0,
    90.0,
    0.0,
    null,
    geoAlt,
    null,
    false,
    0,
    0,
  ];
}

String _states(List<List<dynamic>> vectors) =>
    jsonEncode({'states': vectors});

AircraftService _service(HttpTransport opensky, HttpTransport adsbdb) {
  return AircraftService(
    opensky: OpenSkyClient(opensky),
    adsbdb: AdsbdbClient(adsbdb),
    clock: _clock,
  );
}

void main() {
  group('AircraftService.identify', () {
    test('returns an enriched ok result for a plane overhead', () async {
      final opensky = FakeTransport.json(
        200,
        _states([
          _vec(icao: 'aaaaaa', callsign: 'DLH804', lat: 59.3, lon: 18.0),
        ]),
      );
      final adsbdb = FakeTransport.json(200, _dlh804Body);

      final result = await _service(opensky, adsbdb).identify(_config);

      expect(result.status, IdentifyStatus.ok);
      expect(result.confidence, Confidence.high);
      expect(result.candidate, isNotNull);
      expect(result.candidate!.icao24, 'aaaaaa');
      expect(result.candidate!.registration, 'D-AIZE');
      expect(result.candidate!.enrichmentStatus, EnrichmentStatus.ok);
      expect(result.observedAt, _clock());
    });

    test('still returns ok when enrichment is unavailable', () async {
      final opensky = FakeTransport.json(
        200,
        _states([
          _vec(icao: 'aaaaaa', callsign: 'DLH804', lat: 59.3, lon: 18.0),
        ]),
      );
      final adsbdb = FakeTransport.json(404, '{"response":"unknown aircraft"}');

      final result = await _service(opensky, adsbdb).identify(_config);

      expect(result.status, IdentifyStatus.ok);
      expect(result.candidate, isNotNull);
      expect(
        result.candidate!.enrichmentStatus,
        EnrichmentStatus.unavailable,
      );
      expect(result.candidate!.registration, isNull);
    });

    test('returns a none result when nothing qualifies', () async {
      // ~15 km away at 3000 m -> elevation well below the 45 deg default.
      final opensky = FakeTransport.json(
        200,
        _states([
          _vec(icao: 'cccccc', lat: 59.435, lon: 18.0, geoAlt: 3000.0),
        ]),
      );
      final adsbdb = FakeTransport.json(200, _dlh804Body);

      final result = await _service(opensky, adsbdb).identify(_config);

      expect(result.status, IdentifyStatus.ok);
      expect(result.confidence, Confidence.none);
      expect(result.candidate, isNull);
      expect(result.message, isNotNull);
    });

    test('maps an OpenSky transport timeout to an error result', () async {
      final opensky = FakeTransport.fail(
        const TransportException(TransportErrorKind.timeout),
      );
      final adsbdb = FakeTransport.json(200, _dlh804Body);

      final result = await _service(opensky, adsbdb).identify(_config);

      expect(result.status, IdentifyStatus.error);
      expect(result.errorCode, IdentifyError.openskyTimeout);
      expect(result.message, isNotNull);
      expect(result.candidate, isNull);
    });

    test('rejects an unconfigured location with notConfigured', () async {
      final opensky = FakeTransport.json(200, _states([]));
      final adsbdb = FakeTransport.json(200, _dlh804Body);

      final result = await _service(opensky, adsbdb).identify(
        const IdentifyConfig(latitude: double.nan, longitude: 18.0),
      );

      expect(result.status, IdentifyStatus.error);
      expect(result.errorCode, IdentifyError.notConfigured);
    });
  });
}

const String _dlh804Body = '''
{
  "response": {
    "aircraft": {
      "type": "Airbus A320 214",
      "icao_type": "A320",
      "manufacturer": "Airbus",
      "mode_s": "3C6745",
      "registration": "D-AIZE",
      "registered_owner_country_iso_name": "DE",
      "registered_owner_country_name": "Germany",
      "registered_owner_operator_flag_code": "DLH",
      "registered_owner": "Lufthansa",
      "url_photo": "https://example.com/d-aize.jpg",
      "url_photo_thumbnail": "https://example.com/d-aize-thumb.jpg"
    },
    "flightroute": {
      "callsign": "DLH804",
      "callsign_icao": "DLH804",
      "callsign_iata": "LH804",
      "airline": {
        "name": "Lufthansa",
        "icao": "DLH",
        "iata": "LH",
        "country": "Germany",
        "country_iso": "DE",
        "callsign": "LUFTHANSA"
      },
      "origin": {
        "country_iso_name": "DE",
        "country_name": "Germany",
        "elevation": 364,
        "iata_code": "FRA",
        "icao_code": "EDDF",
        "latitude": 50.0264,
        "longitude": 8.543129,
        "municipality": "Frankfurt",
        "name": "Frankfurt Airport"
      },
      "destination": {
        "country_iso_name": "SE",
        "country_name": "Sweden",
        "elevation": 137,
        "iata_code": "ARN",
        "icao_code": "ESSA",
        "latitude": 59.651901,
        "longitude": 17.918600,
        "municipality": "Stockholm",
        "name": "Stockholm Arlanda Airport"
      }
    }
  }
}
''';

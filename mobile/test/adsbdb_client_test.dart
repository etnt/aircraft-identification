import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:skyoverhead/src/data/adsbdb_client.dart';
import 'package:skyoverhead/src/domain/models.dart';

import 'support/fake_transport.dart';

/// Recorded live response for icao24 3c6745 / callsign DLH804 (2026-07-18).
const String _dlh804Body = '''
{
  "response": {
    "aircraft": {
      "type": "A320 214",
      "icao_type": "A320",
      "manufacturer": "Airbus",
      "registration": "D-AIZE",
      "registered_owner": "Lufthansa",
      "registered_owner_country_name": "Germany",
      "url_photo": "https://airport-data.com/images/aircraft/001/727/001727401.jpg"
    },
    "flightroute": {
      "callsign": "DLH804",
      "airline": { "name": "Lufthansa", "icao": "DLH", "iata": "LH" },
      "origin": {
        "icao_code": "EDDF", "iata_code": "FRA",
        "name": "Frankfurt am Main Airport"
      },
      "destination": {
        "icao_code": "ESSA", "iata_code": "ARN",
        "name": "Stockholm-Arlanda Airport"
      }
    }
  }
}
''';

Candidate _candidate() => const Candidate(
      icao24: '3c6745',
      callsign: 'DLH804',
      altitudeM: 2148.84,
      altitudeSource: AltitudeSource.geometric,
      distanceKm: 3.27,
      bearingDeg: 157.8,
      elevationDeg: 33.3,
      positionAgeS: 3,
    );

void main() {
  group('buildUrl', () {
    test('includes the icao and callsign query', () {
      final url = AdsbdbClient.buildUrl('3c6745', 'DLH804');
      expect(url.host, 'api.adsbdb.com');
      expect(url.path, '/v0/aircraft/3c6745');
      expect(url.queryParameters['callsign'], 'DLH804');
    });

    test('omits the callsign query when absent', () {
      final url = AdsbdbClient.buildUrl('3c6745', null);
      expect(url.queryParameters.containsKey('callsign'), isFalse);
    });
  });

  group('parse', () {
    test('maps the verified DLH804 response', () {
      final fields = AdsbdbClient.parse(jsonDecode(_dlh804Body));
      expect(fields.registration, 'D-AIZE');
      expect(fields.manufacturer, 'Airbus');
      expect(fields.model, 'A320 214');
      expect(fields.registeredOwnerOperator, 'Lufthansa');
      expect(fields.airline, 'Lufthansa');
      expect(fields.photoUrl, contains('001727401.jpg'));
      expect(fields.origin?.iata, 'FRA');
      expect(fields.destination?.icao, 'ESSA');
      expect(fields.destination?.name, 'Stockholm-Arlanda Airport');
    });

    test('returns empty fields for an "unknown aircraft" string response', () {
      final fields = AdsbdbClient.parse({'response': 'unknown aircraft'});
      expect(fields.registration, isNull);
      expect(fields.origin, isNull);
    });
  });

  group('enrich', () {
    test('merges fields and marks status ok on 200', () async {
      final client = AdsbdbClient(FakeTransport.json(200, _dlh804Body));
      final enriched = await client.enrich(_candidate());
      expect(enriched.registration, 'D-AIZE');
      expect(enriched.model, 'A320 214');
      expect(enriched.registeredOwnerOperator, 'Lufthansa');
      expect(enriched.origin?.iata, 'FRA');
      expect(enriched.destination?.iata, 'ARN');
      expect(enriched.enrichmentStatus, EnrichmentStatus.ok);
      // Positional data is preserved.
      expect(enriched.elevationDeg, 33.3);
    });

    test('marks status unavailable on a non-200 response', () async {
      final client = AdsbdbClient(FakeTransport.json(404, '{}'));
      final enriched = await client.enrich(_candidate());
      expect(enriched.registration, isNull);
      expect(enriched.enrichmentStatus, EnrichmentStatus.unavailable);
    });

    test('marks status unavailable on a transport failure', () async {
      final client = AdsbdbClient(
        FakeTransport.fail(Exception('boom')),
      );
      final enriched = await client.enrich(_candidate());
      expect(enriched.enrichmentStatus, EnrichmentStatus.unavailable);
    });
  });
}

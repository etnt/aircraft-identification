import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:skyoverhead/main.dart';
import 'package:skyoverhead/src/data/aircraft_service.dart';
import 'package:skyoverhead/src/data/http.dart';
import 'package:skyoverhead/src/state/identify_controller.dart';

/// Routes requests by host: OpenSky states vs ADSBDB enrichment.
class _RoutingTransport implements HttpTransport {
  final String statesBody;
  final String adsbdbBody;

  _RoutingTransport({required this.statesBody, required this.adsbdbBody});

  @override
  Future<HttpResponse> get(
    Uri url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 12),
    int maxBody = 262144,
  }) async {
    final body = url.host.contains('adsbdb') ? adsbdbBody : statesBody;
    return HttpResponse(
      200,
      const {'content-type': 'application/json'},
      body,
    );
  }
}

/// A single OpenSky-style extended state vector, directly overhead.
List<dynamic> _overhead(int nowSeconds) {
  return <dynamic>[
    '3c6745',
    'DLH804',
    'Germany',
    nowSeconds,
    nowSeconds,
    18.0686, // longitude (matches the default observer)
    59.3293, // latitude
    9950.0,
    false,
    230.0,
    45.0,
    0.0,
    null,
    10000.0,
    null,
    false,
    0,
    0,
  ];
}

const String _adsbdbBody = '''
{
  "response": {
    "aircraft": {
      "type": "Airbus A320 214",
      "icao_type": "A320",
      "manufacturer": "Airbus",
      "mode_s": "3C6745",
      "registration": "D-AIZE",
      "registered_owner": "Lufthansa",
      "url_photo": null,
      "url_photo_thumbnail": null
    },
    "flightroute": {
      "callsign": "DLH804",
      "airline": { "name": "Lufthansa", "icao": "DLH", "iata": "LH" },
      "origin": { "iata_code": "FRA", "icao_code": "EDDF", "name": "Frankfurt" },
      "destination": { "iata_code": "ARN", "icao_code": "ESSA", "name": "Arlanda" }
    }
  }
}
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tap identifies the aircraft overhead end to end', (
    tester,
  ) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final transport = _RoutingTransport(
      statesBody: jsonEncode({
        'states': [_overhead(now)],
      }),
      adsbdbBody: _adsbdbBody,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aircraftServiceProvider.overrideWithValue(
            AircraftService.networked(transport),
          ),
        ],
        child: const SkyOverheadApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Idle prompt first.
    expect(find.text('Point at the sky'), findsOneWidget);

    await tester.tap(find.text("What's overhead?"));
    await tester.pumpAndSettle();

    // The enriched result card is shown.
    expect(find.text('DLH804'), findsOneWidget);
    expect(find.text('Lufthansa'), findsOneWidget);
    expect(find.text('FRA → ARN'), findsOneWidget);
    expect(find.byIcon(Icons.flight_takeoff), findsOneWidget);
  });
}

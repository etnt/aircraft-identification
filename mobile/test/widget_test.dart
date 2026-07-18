import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyoverhead/src/config/identify_config.dart';
import 'package:skyoverhead/src/data/aircraft_service.dart';
import 'package:skyoverhead/src/data/errors.dart';
import 'package:skyoverhead/src/domain/models.dart';
import 'package:skyoverhead/src/state/identify_controller.dart';
import 'package:skyoverhead/src/ui/home_screen.dart';

/// A fake service whose result is chosen per test.
class _FakeService implements AircraftService {
  final IdentifyResult result;
  _FakeService(this.result);

  @override
  Future<IdentifyResult> identify(IdentifyConfig config) async => result;
}

final _observedAt = DateTime.utc(2026, 7, 18);

Candidate _candidate() => const Candidate(
      icao24: '3c6745',
      callsign: 'DLH804',
      registration: 'D-AIZE',
      manufacturer: 'Airbus',
      model: 'A320 214',
      airline: 'Lufthansa',
      origin: Airport(icao: 'EDDF', iata: 'FRA', name: 'Frankfurt'),
      destination: Airport(icao: 'ESSA', iata: 'ARN', name: 'Arlanda'),
      altitudeM: 10000.0,
      altitudeSource: AltitudeSource.geometric,
      distanceKm: 0.5,
      bearingDeg: 45.0,
      elevationDeg: 88.0,
      speedMps: 230.0,
      positionAgeS: 2,
      enrichmentStatus: EnrichmentStatus.ok,
    );

Widget _app(IdentifyResult result) {
  return ProviderScope(
    overrides: [
      aircraftServiceProvider.overrideWithValue(_FakeService(result)),
    ],
    child: const MaterialApp(home: HomeScreen()),
  );
}

void main() {
  testWidgets('shows the idle prompt on first load', (tester) async {
    await tester.pumpWidget(
      _app(IdentifyResult.none(observedAt: _observedAt)),
    );

    expect(find.text("What's overhead?"), findsOneWidget);
    expect(find.text('Point at the sky'), findsOneWidget);
  });

  testWidgets('tap surfaces the result card for a match', (tester) async {
    await tester.pumpWidget(
      _app(
        IdentifyResult.ok(
          confidence: Confidence.high,
          candidate: _candidate(),
          alternatives: const [],
          observedAt: _observedAt,
        ),
      ),
    );

    await tester.tap(find.text("What's overhead?"));
    await tester.pumpAndSettle();

    expect(find.text('DLH804'), findsOneWidget);
    expect(find.text('Lufthansa'), findsOneWidget);
    expect(find.text('High confidence'), findsOneWidget);
    expect(find.text('FRA → ARN'), findsOneWidget);
  });

  testWidgets('tap shows clear-skies empty state for no match', (tester) async {
    await tester.pumpWidget(
      _app(IdentifyResult.none(observedAt: _observedAt)),
    );

    await tester.tap(find.text("What's overhead?"));
    await tester.pumpAndSettle();

    expect(find.text('Clear skies'), findsOneWidget);
  });

  testWidgets('tap shows an error state with retry', (tester) async {
    await tester.pumpWidget(
      _app(
        IdentifyResult.error(
          errorCode: IdentifyError.openskyTimeout,
          message: messageForError(IdentifyError.openskyTimeout),
          observedAt: _observedAt,
        ),
      ),
    );

    await tester.tap(find.text("What's overhead?"));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}


import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyoverhead/src/config/identify_config.dart';
import 'package:skyoverhead/src/data/aircraft_service.dart';
import 'package:skyoverhead/src/data/errors.dart';
import 'package:skyoverhead/src/domain/models.dart';
import 'package:skyoverhead/src/state/identify_controller.dart';

/// A hand fake implementing only the public [AircraftService] surface.
class _FakeService implements AircraftService {
  IdentifyResult? next;
  int calls = 0;

  @override
  Future<IdentifyResult> identify(IdentifyConfig config) async {
    calls++;
    return next!;
  }
}

const _config = IdentifyConfig(latitude: 59.3, longitude: 18.0);
final _observedAt = DateTime.utc(2026, 7, 18);

ProviderContainer _containerWith(_FakeService service) {
  return ProviderContainer(
    overrides: [aircraftServiceProvider.overrideWithValue(service)],
  );
}

Candidate _candidate() => const Candidate(
      icao24: 'aaaaaa',
      callsign: 'DLH804',
      altitudeM: 10000.0,
      altitudeSource: AltitudeSource.geometric,
      distanceKm: 0.5,
      bearingDeg: 0.0,
      elevationDeg: 88.0,
      positionAgeS: 2,
    );

void main() {
  group('IdentifyController', () {
    test('starts idle', () {
      final container = _containerWith(_FakeService());
      addTearDown(container.dispose);

      expect(
        container.read(identifyControllerProvider),
        isA<IdentifyIdle>(),
      );
    });

    test('transitions to success carrying the result', () async {
      final service = _FakeService()
        ..next = IdentifyResult.ok(
          confidence: Confidence.high,
          candidate: _candidate(),
          alternatives: const [],
          observedAt: _observedAt,
        );
      final container = _containerWith(service);
      addTearDown(container.dispose);

      await container
          .read(identifyControllerProvider.notifier)
          .identify(_config);

      final state = container.read(identifyControllerProvider);
      expect(state, isA<IdentifySuccess>());
      expect((state as IdentifySuccess).result.confidence, Confidence.high);
      expect(service.calls, 1);
    });

    test('surfaces a "clear skies" none result as success', () async {
      final service = _FakeService()
        ..next = IdentifyResult.none(observedAt: _observedAt);
      final container = _containerWith(service);
      addTearDown(container.dispose);

      await container
          .read(identifyControllerProvider.notifier)
          .identify(_config);

      final state = container.read(identifyControllerProvider);
      expect(state, isA<IdentifySuccess>());
      expect((state as IdentifySuccess).result.confidence, Confidence.none);
    });

    test('transitions to failure with the error code and message', () async {
      final service = _FakeService()
        ..next = IdentifyResult.error(
          errorCode: IdentifyError.openskyTimeout,
          message: messageForError(IdentifyError.openskyTimeout),
          observedAt: _observedAt,
        );
      final container = _containerWith(service);
      addTearDown(container.dispose);

      await container
          .read(identifyControllerProvider.notifier)
          .identify(_config);

      final state = container.read(identifyControllerProvider);
      expect(state, isA<IdentifyFailure>());
      expect((state as IdentifyFailure).code, IdentifyError.openskyTimeout);
      expect(state.message, isNotEmpty);
    });

    test('reset returns to idle', () async {
      final service = _FakeService()
        ..next = IdentifyResult.none(observedAt: _observedAt);
      final container = _containerWith(service);
      addTearDown(container.dispose);

      final controller =
          container.read(identifyControllerProvider.notifier);
      await controller.identify(_config);
      expect(container.read(identifyControllerProvider), isA<IdentifySuccess>());

      controller.reset();
      expect(container.read(identifyControllerProvider), isA<IdentifyIdle>());
    });
  });
}

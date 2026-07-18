import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyoverhead/src/config/identify_config.dart';
import 'package:skyoverhead/src/data/location_service.dart';
import 'package:skyoverhead/src/state/config_provider.dart';
import 'package:skyoverhead/src/state/location_controller.dart';

/// A fake location service returning a fix or throwing a chosen error.
class _FakeLocationService implements LocationService {
  final LocationFix? fix;
  final LocationException? error;
  _FakeLocationService.fix(this.fix) : error = null;
  _FakeLocationService.failure(this.error) : fix = null;

  @override
  Future<LocationFix> currentFix() async {
    if (error != null) throw error!;
    return fix!;
  }
}

ProviderContainer _containerWith(LocationService service) {
  return ProviderContainer(
    overrides: [locationServiceProvider.overrideWithValue(service)],
  );
}

void main() {
  group('LocationController', () {
    test('starts idle', () {
      final container = _containerWith(
        _FakeLocationService.fix(
          const LocationFix(latitude: 1.0, longitude: 2.0),
        ),
      );
      addTearDown(container.dispose);

      expect(
        container.read(locationControllerProvider),
        isA<LocationIdle>(),
      );
    });

    test('updates the config on a successful fix', () async {
      final container = _containerWith(
        _FakeLocationService.fix(
          const LocationFix(latitude: 40.7, longitude: -74.0, elevationM: 12.0),
        ),
      );
      addTearDown(container.dispose);

      final ok = await container
          .read(locationControllerProvider.notifier)
          .useCurrentLocation();

      expect(ok, isTrue);
      expect(container.read(locationControllerProvider), isA<LocationIdle>());

      final IdentifyConfig config = container.read(identifyConfigProvider);
      expect(config.latitude, 40.7);
      expect(config.longitude, -74.0);
      expect(config.elevationM, 12.0);
    });

    test('reports a failure and leaves the config unchanged', () async {
      final container = _containerWith(
        _FakeLocationService.failure(
          const LocationException(LocationErrorKind.permissionDenied),
        ),
      );
      addTearDown(container.dispose);

      final before = container.read(identifyConfigProvider);
      final ok = await container
          .read(locationControllerProvider.notifier)
          .useCurrentLocation();

      expect(ok, isFalse);
      final state = container.read(locationControllerProvider);
      expect(state, isA<LocationFailed>());
      expect(
        (state as LocationFailed).kind,
        LocationErrorKind.permissionDenied,
      );
      expect(state.message, isNotEmpty);

      final after = container.read(identifyConfigProvider);
      expect(after.latitude, before.latitude);
      expect(after.longitude, before.longitude);
    });

    test('clearError returns to idle', () async {
      final container = _containerWith(
        _FakeLocationService.failure(
          const LocationException(LocationErrorKind.serviceDisabled),
        ),
      );
      addTearDown(container.dispose);

      final controller =
          container.read(locationControllerProvider.notifier);
      await controller.useCurrentLocation();
      expect(container.read(locationControllerProvider), isA<LocationFailed>());

      controller.clearError();
      expect(container.read(locationControllerProvider), isA<LocationIdle>());
    });
  });
}

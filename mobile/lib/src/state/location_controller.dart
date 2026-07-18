/// Controller that fetches the device location and updates the observer
/// [IdentifyConfig], exposing an idle -> locating -> (idle | failed) state.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/location_service.dart';
import 'config_provider.dart';

/// UI-facing state for the "use my location" action.
sealed class LocationUiState {
  const LocationUiState();
}

class LocationIdle extends LocationUiState {
  const LocationIdle();
}

class LocationLocating extends LocationUiState {
  const LocationLocating();
}

class LocationFailed extends LocationUiState {
  final LocationErrorKind kind;
  final String message;
  const LocationFailed(this.kind, this.message);
}

/// The concrete location service; override in tests.
final locationServiceProvider = Provider<LocationService>(
  (ref) => const GeolocatorLocationService(),
);

class LocationController extends StateNotifier<LocationUiState> {
  final Ref _ref;
  final LocationService _service;

  LocationController(this._ref, this._service) : super(const LocationIdle());

  /// Fetch a fix and update [identifyConfigProvider]. Returns true on
  /// success. Ignores re-entrant calls while already locating.
  Future<bool> useCurrentLocation() async {
    if (state is LocationLocating) return false;
    state = const LocationLocating();
    try {
      final fix = await _service.currentFix();
      final config = _ref.read(identifyConfigProvider);
      _ref.read(identifyConfigProvider.notifier).state = config.copyWith(
        latitude: fix.latitude,
        longitude: fix.longitude,
        elevationM: fix.elevationM ?? config.elevationM,
      );
      state = const LocationIdle();
      return true;
    } on LocationException catch (e) {
      state = LocationFailed(e.kind, messageForLocationError(e.kind));
      return false;
    }
  }

  /// Clear a previous failure back to idle.
  void clearError() => state = const LocationIdle();
}

final locationControllerProvider =
    StateNotifierProvider<LocationController, LocationUiState>((ref) {
  return LocationController(ref, ref.watch(locationServiceProvider));
});

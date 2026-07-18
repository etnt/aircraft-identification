/// Device location access behind a small interface so the UI and tests
/// never touch the plugin directly.
library;

import 'package:geolocator/geolocator.dart';

/// Why a location request could not be fulfilled.
enum LocationErrorKind {
  /// Location services are turned off on the device.
  serviceDisabled,

  /// The user declined the permission this time.
  permissionDenied,

  /// The user declined permanently; only Settings can re-enable it.
  permissionDeniedForever,

  /// A fix could not be obtained (timeout / hardware).
  unavailable,
}

class LocationException implements Exception {
  final LocationErrorKind kind;
  const LocationException(this.kind);

  @override
  String toString() => 'LocationException(${kind.name})';
}

/// A single position fix.
class LocationFix {
  final double latitude;
  final double longitude;
  final double? elevationM;

  const LocationFix({
    required this.latitude,
    required this.longitude,
    this.elevationM,
  });
}

/// Obtains the observer's current position.
abstract class LocationService {
  Future<LocationFix> currentFix();
}

/// Friendly message for each [LocationErrorKind].
String messageForLocationError(LocationErrorKind kind) {
  switch (kind) {
    case LocationErrorKind.serviceDisabled:
      return 'Location services are turned off. Enable them or enter a '
          'location manually.';
    case LocationErrorKind.permissionDenied:
      return 'Location permission was denied. Grant it or enter a location '
          'manually.';
    case LocationErrorKind.permissionDeniedForever:
      return 'Location permission is blocked. Enable it in Settings or enter '
          'a location manually.';
    case LocationErrorKind.unavailable:
      return 'Could not get a location fix. Try again or enter one manually.';
  }
}

/// [LocationService] backed by the `geolocator` plugin.
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<LocationFix> currentFix() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationException(LocationErrorKind.serviceDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(LocationErrorKind.permissionDeniedForever);
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException(LocationErrorKind.permissionDenied);
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return LocationFix(
        latitude: position.latitude,
        longitude: position.longitude,
        elevationM: position.altitude,
      );
    } catch (_) {
      throw const LocationException(LocationErrorKind.unavailable);
    }
  }
}

/// Pure geometry and OpenSky state-vector normalization.
///
/// A direct port of the side-effect-free parts of the Erlang
/// `aircraft_id_geo` module. Everything here is deterministic and unit
/// testable without any network access.
library;

import 'dart:math' as math;

import 'models.dart';

/// Mean Earth radius (km), matching the Erlang constant.
const double earthKm = 6371.0088;

/// Kilometres per degree of latitude, matching the Erlang constant.
const double kmPerDegLat = 111.32;

double _deg2rad(double d) => d * math.pi / 180.0;

double _rad2deg(double r) => r * 180.0 / math.pi;

/// Normalize a bearing to the 0..360 range.
double norm360(double deg) {
  final v = deg % 360.0;
  return v < 0 ? v + 360.0 : v;
}

/// Build the OpenSky bounding box for a search radius (km) around a point.
/// Longitude is not clamped; antimeridian handling is out of scope for MVP.
BoundingBox boundingBox(double lat, double lon, double radiusKm) {
  final latDelta = radiusKm / kmPerDegLat;
  final lonDelta = radiusKm / (kmPerDegLat * math.cos(_deg2rad(lat)));
  return BoundingBox(
    south: (lat - latDelta).clamp(-90.0, 90.0).toDouble(),
    north: (lat + latDelta).clamp(-90.0, 90.0).toDouble(),
    west: lon - lonDelta,
    east: lon + lonDelta,
  );
}

/// Horizontal great-circle distance in kilometres (haversine).
double distanceKm(double lat1, double lon1, double lat2, double lon2) {
  final p1 = _deg2rad(lat1);
  final p2 = _deg2rad(lat2);
  final dp = _deg2rad(lat2 - lat1);
  final dl = _deg2rad(lon2 - lon1);
  final a = math.sin(dp / 2) * math.sin(dp / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthKm * c;
}

/// Initial bearing from the observer to the target, degrees 0..360.
double bearingDeg(double lat1, double lon1, double lat2, double lon2) {
  final p1 = _deg2rad(lat1);
  final p2 = _deg2rad(lat2);
  final dl = _deg2rad(lon2 - lon1);
  final y = math.sin(dl) * math.cos(p2);
  final x = math.cos(p1) * math.sin(p2) -
      math.sin(p1) * math.cos(p2) * math.cos(dl);
  return norm360(_rad2deg(math.atan2(y, x)));
}

/// Elevation angle in degrees from horizontal distance and relative height (m).
double elevationDeg(double relHeightM, double horizM) {
  if (horizM == 0.0) return 90.0;
  return _rad2deg(math.atan2(relHeightM, horizM));
}

/// Normalize one raw OpenSky state vector (a decoded JSON array) into an
/// [AircraftState]. Missing or wrongly-typed elements become `null`.
AircraftState parseState(List<dynamic> vec) {
  return AircraftState(
    icao24: _str(_at(vec, 0)),
    callsign: _trim(_str(_at(vec, 1))),
    timePosition: _intOrNull(_at(vec, 3)),
    lastContact: _intOrNull(_at(vec, 4)),
    longitude: _numOrNull(_at(vec, 5)),
    latitude: _numOrNull(_at(vec, 6)),
    baroAltitude: _numOrNull(_at(vec, 7)),
    onGround: _boolOrNull(_at(vec, 8)),
    velocity: _numOrNull(_at(vec, 9)),
    trueTrack: _numOrNull(_at(vec, 10)),
    verticalRate: _numOrNull(_at(vec, 11)),
    geoAltitude: _numOrNull(_at(vec, 13)),
    positionSource: _intOrNull(_at(vec, 16)),
    category: _intOrNull(_at(vec, 17)),
  );
}

Object? _at(List<dynamic> list, int index) =>
    index >= 0 && index < list.length ? list[index] : null;

String? _str(Object? v) => v is String ? v : null;

String? _trim(String? v) {
  if (v == null) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

double? _numOrNull(Object? v) => v is num ? v.toDouble() : null;

int? _intOrNull(Object? v) => v is num ? v.toInt() : null;

bool? _boolOrNull(Object? v) => v is bool ? v : null;

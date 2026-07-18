/// Presentation helpers that turn raw candidate numbers into friendly,
/// human-readable strings. Kept separate from widgets so they are easy to
/// unit test.
library;

import '../domain/models.dart';

/// A 16-point compass label for a bearing in degrees (0 = north).
String compassLabel(double bearingDeg) {
  const points = <String>[
    'N', 'NNE', 'NE', 'ENE',
    'E', 'ESE', 'SE', 'SSE',
    'S', 'SSW', 'SW', 'WSW',
    'W', 'WNW', 'NW', 'NNW',
  ];
  final normalized = bearingDeg % 360.0;
  final index = ((normalized / 22.5) + 0.5).floor() % 16;
  return points[index];
}

/// e.g. "NE · 45°".
String bearingText(double bearingDeg) {
  final rounded = bearingDeg.round() % 360;
  return '${compassLabel(bearingDeg)} · $rounded°';
}

/// Distance in km with adaptive precision.
String distanceText(double distanceKm) {
  if (distanceKm < 1.0) {
    return '${(distanceKm * 1000).round()} m';
  }
  if (distanceKm < 10.0) {
    return '${distanceKm.toStringAsFixed(1)} km';
  }
  return '${distanceKm.round()} km';
}

/// Altitude in metres, annotated with its source when barometric.
String altitudeText(double altitudeM, AltitudeSource source) {
  final metres = '${altitudeM.round()} m';
  switch (source) {
    case AltitudeSource.barometric:
      return '$metres (baro)';
    case AltitudeSource.geometric:
    case AltitudeSource.none:
      return metres;
  }
}

/// Elevation angle above the horizon.
String elevationText(double elevationDeg) => '${elevationDeg.round()}°';

/// Ground speed in km/h, or null when unknown.
String? speedText(double? speedMps) {
  if (speedMps == null) return null;
  return '${(speedMps * 3.6).round()} km/h';
}

/// A short headline for the candidate: callsign, else registration, else icao.
String candidateHeadline(Candidate c) {
  final callsign = c.callsign?.trim();
  if (callsign != null && callsign.isNotEmpty) return callsign;
  final reg = c.registration?.trim();
  if (reg != null && reg.isNotEmpty) return reg;
  return c.icao24.toUpperCase();
}

/// Aircraft type + registration subtitle, e.g. "Airbus A320 · D-AIZE".
String? aircraftSubtitle(Candidate c) {
  final parts = <String>[];
  final model = c.model?.trim();
  final manufacturer = c.manufacturer?.trim();
  if (model != null && model.isNotEmpty) {
    if (manufacturer != null &&
        manufacturer.isNotEmpty &&
        !model.toLowerCase().startsWith(manufacturer.toLowerCase())) {
      parts.add('$manufacturer $model');
    } else {
      parts.add(model);
    }
  } else if (manufacturer != null && manufacturer.isNotEmpty) {
    parts.add(manufacturer);
  }
  final reg = c.registration?.trim();
  if (reg != null && reg.isNotEmpty) parts.add(reg);
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Route as "FRA → ARN" using the best available airport code, or null.
String? routeText(Candidate c) {
  final from = _airportCode(c.origin);
  final to = _airportCode(c.destination);
  if (from == null && to == null) return null;
  return '${from ?? '?'} → ${to ?? '?'}';
}

String? _airportCode(Airport? airport) {
  if (airport == null) return null;
  final iata = airport.iata?.trim();
  if (iata != null && iata.isNotEmpty) return iata;
  final icao = airport.icao?.trim();
  if (icao != null && icao.isNotEmpty) return icao;
  return null;
}

/// Short human label for a confidence level.
String confidenceLabel(Confidence confidence) {
  switch (confidence) {
    case Confidence.high:
      return 'High confidence';
    case Confidence.medium:
      return 'Likely';
    case Confidence.ambiguous:
      return 'Ambiguous';
    case Confidence.none:
      return 'No match';
  }
}

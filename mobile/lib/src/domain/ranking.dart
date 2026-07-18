/// Candidate building, filtering, ranking, and confidence classification.
///
/// A direct port of the selection logic in the Erlang `aircraft_id_geo`
/// module (`select/4` and friends). Pure and side-effect free.
library;

import 'dart:math' as math;

import '../config/identify_config.dart';
import 'geo.dart' as geo;
import 'models.dart';

/// Turn a list of raw OpenSky state vectors into a ranked [Selection].
///
/// [rawStates] is the decoded `states` array; each element is itself a
/// JSON array. [now] is the current Unix time in seconds.
Selection select(
  List<dynamic> rawStates,
  Observer observer,
  int now,
  IdentifyConfig config,
) {
  final candidates = <Candidate>[];
  for (final raw in rawStates) {
    if (raw is! List) continue;
    final state = geo.parseState(raw);
    final candidate = _build(state, observer, now);
    if (candidate == null) continue;
    if (_passes(candidate, config)) candidates.add(candidate);
  }
  _sort(candidates);
  return _classify(candidates, config);
}

Candidate? _build(AircraftState state, Observer observer, int now) {
  final icao = state.icao24;
  final lat = state.latitude;
  final lon = state.longitude;
  final tpos = state.timePosition;
  final (alt, source) = _altitude(state);

  if (icao == null ||
      lat == null ||
      lon == null ||
      tpos == null ||
      alt == null ||
      state.onGround == true) {
    return null;
  }

  final rel = alt - observer.elevM;
  final dist = geo.distanceKm(observer.lat, observer.lon, lat, lon);
  final horizM = dist * 1000.0;
  final brg = geo.bearingDeg(observer.lat, observer.lon, lat, lon);
  final elev = geo.elevationDeg(rel, horizM);

  return Candidate(
    icao24: icao,
    callsign: state.callsign,
    altitudeM: alt,
    altitudeSource: source,
    distanceKm: _round(dist, 2),
    bearingDeg: _round(brg, 1),
    elevationDeg: _round(elev, 1),
    trackDeg: state.trueTrack,
    speedMps: state.velocity,
    positionAgeS: now - tpos,
  );
}

bool _passes(Candidate c, IdentifyConfig config) {
  return c.elevationDeg > 0.0 &&
      c.elevationDeg >= config.minElevationDeg &&
      c.positionAgeS >= 0 &&
      c.positionAgeS <= config.maxPositionAgeS &&
      c.distanceKm <= config.effectiveRadiusKm;
}

/// Elevation desc, then freshness (age asc), then distance asc.
void _sort(List<Candidate> candidates) {
  candidates.sort((a, b) {
    if (a.elevationDeg != b.elevationDeg) {
      return b.elevationDeg.compareTo(a.elevationDeg);
    }
    if (a.positionAgeS != b.positionAgeS) {
      return a.positionAgeS.compareTo(b.positionAgeS);
    }
    return a.distanceKm.compareTo(b.distanceKm);
  });
}

Selection _classify(List<Candidate> candidates, IdentifyConfig config) {
  if (candidates.isEmpty) return Selection.empty;
  final primary = candidates.first;
  final rest = candidates.sublist(1);
  return Selection(
    confidence: _confidence(primary, rest, config),
    candidate: primary,
    alternatives: rest.take(3).toList(),
  );
}

Confidence _confidence(
  Candidate primary,
  List<Candidate> rest,
  IdentifyConfig config,
) {
  final lead = _lead(primary, rest);
  if (rest.isNotEmpty && lead <= config.ambiguityMarginDeg) {
    return Confidence.ambiguous;
  }
  if (primary.elevationDeg >= 60.0 &&
      primary.positionAgeS <= 10 &&
      lead >= 8.0) {
    return Confidence.high;
  }
  return Confidence.medium;
}

/// Elevation gap to the runner-up; infinite when there is only one candidate.
double _lead(Candidate primary, List<Candidate> rest) {
  if (rest.isEmpty) return double.infinity;
  return primary.elevationDeg - rest.first.elevationDeg;
}

/// Prefer geometric (GPS) altitude, fall back to barometric.
(double?, AltitudeSource) _altitude(AircraftState state) {
  if (state.geoAltitude != null) {
    return (state.geoAltitude, AltitudeSource.geometric);
  }
  if (state.baroAltitude != null) {
    return (state.baroAltitude, AltitudeSource.barometric);
  }
  return (null, AltitudeSource.none);
}

double _round(double v, int places) {
  final f = math.pow(10, places).toDouble();
  return (v * f).round() / f;
}

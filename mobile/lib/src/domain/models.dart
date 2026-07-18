/// Domain models for the aircraft identification pipeline.
///
/// These mirror the data shapes produced by the `aircraft_id` Erlang
/// library (see ../../../plans/aircraft_identification.md), so the Dart
/// port stays behaviourally aligned with the reference implementation.
library;

/// How confident the pick is, mirroring the library's confidence labels.
enum Confidence { high, medium, ambiguous, none }

/// Which altitude field the candidate's altitude came from.
enum AltitudeSource { geometric, barometric, none }

/// Result of an enrichment lookup for the primary candidate.
enum EnrichmentStatus { ok, unavailable }

/// The fixed observer location an identification is relative to.
class Observer {
  final double lat;
  final double lon;

  /// Observer height above sea level in metres.
  final double elevM;

  const Observer({required this.lat, required this.lon, this.elevM = 0.0});
}

/// A normalized OpenSky state vector. Fields are nullable because any
/// element of the raw JSON array may be missing or `null`.
class AircraftState {
  final String? icao24;
  final String? callsign;
  final int? timePosition;
  final int? lastContact;
  final double? longitude;
  final double? latitude;
  final double? baroAltitude;
  final bool? onGround;
  final double? velocity;
  final double? trueTrack;
  final double? verticalRate;
  final double? geoAltitude;
  final int? positionSource;
  final int? category;

  const AircraftState({
    this.icao24,
    this.callsign,
    this.timePosition,
    this.lastContact,
    this.longitude,
    this.latitude,
    this.baroAltitude,
    this.onGround,
    this.velocity,
    this.trueTrack,
    this.verticalRate,
    this.geoAltitude,
    this.positionSource,
    this.category,
  });
}

/// An airport reference used in route enrichment.
class Airport {
  final String? icao;
  final String? iata;
  final String? name;

  const Airport({this.icao, this.iata, this.name});
}

/// A ranked aircraft candidate. Positional fields come from OpenSky;
/// the enrichment fields (registration, model, route, ...) start `null`
/// and are populated later by the ADSBDB data layer.
class Candidate {
  final String icao24;
  final String? callsign;
  final String? registration;
  final String? manufacturer;
  final String? model;
  final String? airline;
  final String? registeredOwnerOperator;
  final Airport? origin;
  final Airport? destination;
  final double altitudeM;
  final AltitudeSource altitudeSource;
  final double distanceKm;
  final double bearingDeg;
  final double elevationDeg;
  final double? trackDeg;
  final double? speedMps;
  final int positionAgeS;
  final String? photoUrl;
  final EnrichmentStatus? enrichmentStatus;

  const Candidate({
    required this.icao24,
    this.callsign,
    this.registration,
    this.manufacturer,
    this.model,
    this.airline,
    this.registeredOwnerOperator,
    this.origin,
    this.destination,
    required this.altitudeM,
    required this.altitudeSource,
    required this.distanceKm,
    required this.bearingDeg,
    required this.elevationDeg,
    this.trackDeg,
    this.speedMps,
    required this.positionAgeS,
    this.photoUrl,
    this.enrichmentStatus,
  });

  Candidate copyWith({
    String? registration,
    String? manufacturer,
    String? model,
    String? airline,
    String? registeredOwnerOperator,
    Airport? origin,
    Airport? destination,
    String? photoUrl,
    EnrichmentStatus? enrichmentStatus,
  }) {
    return Candidate(
      icao24: icao24,
      callsign: callsign,
      registration: registration ?? this.registration,
      manufacturer: manufacturer ?? this.manufacturer,
      model: model ?? this.model,
      airline: airline ?? this.airline,
      registeredOwnerOperator:
          registeredOwnerOperator ?? this.registeredOwnerOperator,
      origin: origin ?? this.origin,
      destination: destination ?? this.destination,
      altitudeM: altitudeM,
      altitudeSource: altitudeSource,
      distanceKm: distanceKm,
      bearingDeg: bearingDeg,
      elevationDeg: elevationDeg,
      trackDeg: trackDeg,
      speedMps: speedMps,
      positionAgeS: positionAgeS,
      photoUrl: photoUrl ?? this.photoUrl,
      enrichmentStatus: enrichmentStatus ?? this.enrichmentStatus,
    );
  }
}

/// A geographic bounding box (OpenSky query footprint).
class BoundingBox {
  final double south;
  final double west;
  final double north;
  final double east;

  const BoundingBox({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });
}

/// The ranked outcome: the best candidate (if any), its confidence, and
/// up to three alternatives.
class Selection {
  final Confidence confidence;
  final Candidate? candidate;
  final List<Candidate> alternatives;

  const Selection({
    required this.confidence,
    required this.candidate,
    required this.alternatives,
  });

  static const Selection empty = Selection(
    confidence: Confidence.none,
    candidate: null,
    alternatives: [],
  );
}

/// Whether an identification completed normally or failed.
enum IdentifyStatus { ok, error }

/// The top-level result of a single `identify` call, mirroring the map
/// returned by the Erlang `aircraft_id` facade.
///
/// * `status == ok` with `confidence == none` is a normal "clear skies"
///   outcome (no aircraft qualified), carrying a friendly [message].
/// * `status == error` carries an [errorCode] plus friendly [message].
class IdentifyResult {
  final IdentifyStatus status;
  final Confidence confidence;
  final DateTime observedAt;
  final Candidate? candidate;
  final List<Candidate> alternatives;
  final String? message;

  /// Set only when [status] is [IdentifyStatus.error].
  final Object? errorCode;

  const IdentifyResult({
    required this.status,
    required this.confidence,
    required this.observedAt,
    this.candidate,
    this.alternatives = const [],
    this.message,
    this.errorCode,
  });

  bool get isOk => status == IdentifyStatus.ok;
  bool get hasCandidate => candidate != null;

  /// A successful pick with a candidate.
  factory IdentifyResult.ok({
    required Confidence confidence,
    required Candidate candidate,
    required List<Candidate> alternatives,
    required DateTime observedAt,
  }) {
    return IdentifyResult(
      status: IdentifyStatus.ok,
      confidence: confidence,
      observedAt: observedAt,
      candidate: candidate,
      alternatives: alternatives,
    );
  }

  /// A successful call that found nothing overhead.
  factory IdentifyResult.none({
    required DateTime observedAt,
    String message = 'No aircraft overhead right now.',
  }) {
    return IdentifyResult(
      status: IdentifyStatus.ok,
      confidence: Confidence.none,
      observedAt: observedAt,
      message: message,
    );
  }

  /// A failed call carrying a stable error code and friendly message.
  factory IdentifyResult.error({
    required Object errorCode,
    required String message,
    required DateTime observedAt,
  }) {
    return IdentifyResult(
      status: IdentifyStatus.error,
      confidence: Confidence.none,
      observedAt: observedAt,
      message: message,
      errorCode: errorCode,
    );
  }
}


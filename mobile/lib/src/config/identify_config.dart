/// Caller-supplied configuration for an identification, mirroring the
/// Erlang `aircraft_id_config` keys and defaults.
class IdentifyConfig {
  /// Observer latitude in degrees (-90..90).
  final double latitude;

  /// Observer longitude in degrees (-180..180).
  final double longitude;

  /// Observer height above sea level in metres.
  final double elevationM;

  /// Horizontal query radius in km (clamped to 0.1..50.0 on use).
  final double searchRadiusKm;

  /// Reject positions older than this many seconds.
  final int maxPositionAgeS;

  /// Minimum elevation angle above the horizon to be considered overhead.
  final double minElevationDeg;

  /// Elevation gap below which the top two candidates are "ambiguous".
  final double ambiguityMarginDeg;

  const IdentifyConfig({
    required this.latitude,
    required this.longitude,
    this.elevationM = 0.0,
    this.searchRadiusKm = 30.0,
    this.maxPositionAgeS = 20,
    this.minElevationDeg = 18.0,
    this.ambiguityMarginDeg = 8.0,
  });

  /// Radius clamped to the OpenSky-friendly range, matching the library.
  double get effectiveRadiusKm => searchRadiusKm.clamp(0.1, 50.0).toDouble();

  IdentifyConfig copyWith({
    double? latitude,
    double? longitude,
    double? elevationM,
    double? searchRadiusKm,
    int? maxPositionAgeS,
    double? minElevationDeg,
    double? ambiguityMarginDeg,
  }) {
    return IdentifyConfig(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      elevationM: elevationM ?? this.elevationM,
      searchRadiusKm: searchRadiusKm ?? this.searchRadiusKm,
      maxPositionAgeS: maxPositionAgeS ?? this.maxPositionAgeS,
      minElevationDeg: minElevationDeg ?? this.minElevationDeg,
      ambiguityMarginDeg: ambiguityMarginDeg ?? this.ambiguityMarginDeg,
    );
  }
}

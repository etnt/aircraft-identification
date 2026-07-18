import 'package:flutter_test/flutter_test.dart';
import 'package:skyoverhead/src/config/identify_config.dart';
import 'package:skyoverhead/src/domain/models.dart';
import 'package:skyoverhead/src/domain/ranking.dart';

/// Build an OpenSky-style state vector (extended, 18 elements).
List<dynamic> vec({
  required String icao,
  required String callsign,
  required double lat,
  required double lon,
  required double geoAlt,
  required int timePos,
  bool onGround = false,
  double velocity = 100.0,
  double track = 90.0,
}) {
  return <dynamic>[
    icao, // 0 icao24
    callsign, // 1 callsign
    'Testland', // 2 origin_country
    timePos, // 3 time_position
    timePos, // 4 last_contact
    lon, // 5 longitude
    lat, // 6 latitude
    geoAlt - 50, // 7 baro_altitude
    onGround, // 8 on_ground
    velocity, // 9 velocity
    track, // 10 true_track
    0.0, // 11 vertical_rate
    null, // 12 sensors
    geoAlt, // 13 geo_altitude
    null, // 14 squawk
    false, // 15 spi
    0, // 16 position_source
    0, // 17 category
  ];
}

void main() {
  const now = 1000000;
  const observer = Observer(lat: 59.3, lon: 18.0, elevM: 0.0);
  const config = IdentifyConfig(latitude: 59.3, longitude: 18.0);

  test('ranks highest elevation first with high confidence', () {
    final states = <dynamic>[
      // ~5 km east, still high but lower elevation.
      vec(
        icao: 'bbbbbb',
        callsign: 'BBB',
        lat: 59.3,
        lon: 18.088,
        geoAlt: 10000.0,
        timePos: now,
      ),
      // Directly overhead -> ~90 deg elevation.
      vec(
        icao: 'aaaaaa',
        callsign: 'AAA',
        lat: 59.3,
        lon: 18.0,
        geoAlt: 10000.0,
        timePos: now,
      ),
    ];

    final selection = select(states, observer, now, config);

    expect(selection.candidate, isNotNull);
    expect(selection.candidate!.icao24, 'aaaaaa');
    expect(selection.confidence, Confidence.high);
    expect(selection.alternatives, hasLength(1));
    expect(selection.alternatives.first.icao24, 'bbbbbb');
    expect(selection.candidate!.altitudeSource, AltitudeSource.geometric);
  });

  test('returns none when all candidates are below the elevation threshold', () {
    final states = <dynamic>[
      // ~15 km away, low altitude -> ~11 deg elevation, below the 45 default.
      vec(
        icao: 'cccccc',
        callsign: 'CCC',
        lat: 59.3,
        lon: 18.264,
        geoAlt: 3000.0,
        timePos: now,
      ),
    ];

    final selection = select(states, observer, now, config);

    expect(selection.confidence, Confidence.none);
    expect(selection.candidate, isNull);
    expect(selection.alternatives, isEmpty);
  });

  test('rejects aircraft that are on the ground', () {
    final states = <dynamic>[
      vec(
        icao: 'dddddd',
        callsign: 'DDD',
        lat: 59.3,
        lon: 18.0,
        geoAlt: 10000.0,
        timePos: now,
        onGround: true,
      ),
    ];

    final selection = select(states, observer, now, config);

    expect(selection.candidate, isNull);
    expect(selection.confidence, Confidence.none);
  });

  test('rejects stale positions older than maxPositionAgeS', () {
    final states = <dynamic>[
      vec(
        icao: 'eeeeee',
        callsign: 'EEE',
        lat: 59.3,
        lon: 18.0,
        geoAlt: 10000.0,
        timePos: now - 60, // 60s old, default max is 20s
      ),
    ];

    final selection = select(states, observer, now, config);

    expect(selection.candidate, isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:skyoverhead/src/domain/geo.dart';

void main() {
  group('distanceKm', () {
    test('one degree of latitude is about 111.19 km', () {
      expect(distanceKm(0.0, 0.0, 1.0, 0.0), closeTo(111.19, 0.1));
    });

    test('same point is zero', () {
      expect(distanceKm(59.3, 18.0, 59.3, 18.0), closeTo(0.0, 1e-9));
    });
  });

  group('bearingDeg', () {
    test('due north is ~0 degrees', () {
      expect(bearingDeg(0.0, 0.0, 1.0, 0.0), closeTo(0.0, 0.001));
    });

    test('due east is ~90 degrees', () {
      expect(bearingDeg(0.0, 0.0, 0.0, 1.0), closeTo(90.0, 0.001));
    });
  });

  group('elevationDeg', () {
    test('equal height and horizontal distance is 45 degrees', () {
      expect(elevationDeg(1000.0, 1000.0), closeTo(45.0, 1e-9));
    });

    test('zero horizontal distance is straight up (90)', () {
      expect(elevationDeg(5000.0, 0.0), 90.0);
    });
  });

  group('boundingBox', () {
    test('brackets the observer point', () {
      final box = boundingBox(59.3, 18.0, 20.0);
      expect(box.south, lessThan(59.3));
      expect(box.north, greaterThan(59.3));
      expect(box.west, lessThan(18.0));
      expect(box.east, greaterThan(18.0));
    });
  });

  group('parseState', () {
    test('handles nulls and trims the callsign', () {
      final vec = <dynamic>[
        '3c6745', // 0 icao24
        'DLH804  ', // 1 callsign (padded)
        'Germany', // 2 origin_country
        1784381895, // 3 time_position
        1784381896, // 4 last_contact
        18.0, // 5 longitude
        59.3, // 6 latitude
        2100.0, // 7 baro_altitude
        false, // 8 on_ground
        132.29, // 9 velocity
        10.3, // 10 true_track
        null, // 11 vertical_rate
        null, // 12 sensors
        2148.84, // 13 geo_altitude
        null, // 14 squawk
        false, // 15 spi
        0, // 16 position_source
      ];
      final state = parseState(vec);
      expect(state.icao24, '3c6745');
      expect(state.callsign, 'DLH804');
      expect(state.latitude, 59.3);
      expect(state.geoAltitude, 2148.84);
      expect(state.verticalRate, isNull);
      expect(state.onGround, false);
    });

    test('missing trailing elements become null', () {
      final state = parseState(<dynamic>['abcdef', null]);
      expect(state.icao24, 'abcdef');
      expect(state.callsign, isNull);
      expect(state.latitude, isNull);
    });
  });
}

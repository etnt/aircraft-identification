import 'package:flutter_test/flutter_test.dart';
import 'package:skyoverhead/src/config/identify_config.dart';
import 'package:skyoverhead/src/data/errors.dart';
import 'package:skyoverhead/src/data/http.dart';
import 'package:skyoverhead/src/data/opensky_client.dart';

import 'support/fake_transport.dart';

void main() {
  const config = IdentifyConfig(latitude: 59.3, longitude: 18.0);

  group('buildUrl', () {
    test('targets the OpenSky states endpoint with a bounding box', () {
      final url = OpenSkyClient.buildUrl(config);
      expect(url.host, 'opensky-network.org');
      expect(url.path, '/api/states/all');
      expect(url.queryParameters.keys,
          containsAll(['lamin', 'lomin', 'lamax', 'lomax', 'extended']));
      expect(url.queryParameters['extended'], '1');
      expect(double.parse(url.queryParameters['lamin']!), lessThan(59.3));
      expect(double.parse(url.queryParameters['lamax']!), greaterThan(59.3));
    });
  });

  group('parseStates', () {
    test('extracts the states list', () {
      final states = OpenSkyClient.parseStates({
        'time': 1784381895,
        'states': [
          ['abc', 'AAA'],
          ['def', 'BBB'],
        ],
      });
      expect(states, hasLength(2));
    });

    test('returns an empty list when states is null', () {
      expect(OpenSkyClient.parseStates({'states': null}), isEmpty);
    });

    test('returns an empty list for non-map input', () {
      expect(OpenSkyClient.parseStates('nope'), isEmpty);
    });
  });

  group('fetchStates', () {
    test('returns the states list on 200', () async {
      final client = OpenSkyClient(
        FakeTransport.json(200, '{"states":[["abc","AAA"]]}'),
      );
      final states = await client.fetchStates(config);
      expect(states, hasLength(1));
    });

    test('maps 429 to openskyRateLimited', () async {
      final client = OpenSkyClient(FakeTransport.json(429, ''));
      expect(
        () => client.fetchStates(config),
        throwsA(isA<IdentifyException>().having(
            (e) => e.code, 'code', IdentifyError.openskyRateLimited)),
      );
    });

    test('maps 401/403 to openskyUnauthorized', () async {
      final client = OpenSkyClient(FakeTransport.json(403, ''));
      expect(
        () => client.fetchStates(config),
        throwsA(isA<IdentifyException>().having(
            (e) => e.code, 'code', IdentifyError.openskyUnauthorized)),
      );
    });

    test('maps a transport timeout to openskyTimeout', () async {
      final client = OpenSkyClient(
        FakeTransport.fail(
            const TransportException(TransportErrorKind.timeout)),
      );
      expect(
        () => client.fetchStates(config),
        throwsA(isA<IdentifyException>().having(
            (e) => e.code, 'code', IdentifyError.openskyTimeout)),
      );
    });

    test('maps malformed JSON to openskyBadResponse', () async {
      final client = OpenSkyClient(FakeTransport.json(200, 'not json {'));
      expect(
        () => client.fetchStates(config),
        throwsA(isA<IdentifyException>().having(
            (e) => e.code, 'code', IdentifyError.openskyBadResponse)),
      );
    });
  });

  group('authentication', () {
    test('stays anonymous with no token provider', () async {
      final fake = FakeTransport.json(200, '{"states":[]}');
      await OpenSkyClient(fake).fetchStates(config);
      expect(fake.lastHeaders, isNotNull);
      expect(fake.lastHeaders!.containsKey('authorization'), isFalse);
    });

    test('adds a bearer header when a token is provided', () async {
      final fake = FakeTransport.json(200, '{"states":[]}');
      final client = OpenSkyClient(
        fake,
        tokenProvider: () async => 'secret-token',
      );
      await client.fetchStates(config);
      expect(fake.lastHeaders!['authorization'], 'Bearer secret-token');
    });

    test('stays anonymous when the token provider returns null', () async {
      final fake = FakeTransport.json(200, '{"states":[]}');
      final client = OpenSkyClient(fake, tokenProvider: () async => null);
      await client.fetchStates(config);
      expect(fake.lastHeaders!.containsKey('authorization'), isFalse);
    });
  });
}

import 'package:alive_eye/services/gtfs_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decodePolyline', () {
    test('decodes the reference polyline', () {
      final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');

      expect(points, hasLength(3));
      expect(points[0].latitude, closeTo(38.5, 1e-5));
      expect(points[0].longitude, closeTo(-120.2, 1e-5));
      expect(points[2].latitude, closeTo(43.252, 1e-5));
      expect(points[2].longitude, closeTo(-126.453, 1e-5));
    });

    test('returns nothing for empty or truncated input', () {
      expect(decodePolyline(''), isEmpty);
      expect(decodePolyline('_p~iF'), isEmpty);
    });

    test('round-trips what the build tool encodes', () {
      const points = [(-23.482099, -46.71827), (-23.485653, -46.71567), (-23.523084, -46.653938)];

      final decoded = decodePolyline(encodePolyline(points));

      expect(decoded, hasLength(3));
      for (var i = 0; i < points.length; i++) {
        expect(decoded[i].latitude, closeTo(points[i].$1, 1e-5));
        expect(decoded[i].longitude, closeTo(points[i].$2, 1e-5));
      }
    });
  });

  group('parseGtfsRoutes', () {
    const text = '''
# alive_eye routes v1
8600-10\t0\t101,102,103\t
8600-10\t1\t201,202,203\t_p~iF~ps|U_ulLnnqC
477A-10\t0\t301,302\t
bad line
9999-10\t0\t1\t
''';

    test('parses every route and skips malformed rows', () {
      final routes = parseGtfsRoutes(text);

      expect(routes.isEmpty, isFalse);
      expect(routes.length, 3);
      expect(routes.match('9999-10', direction: 1), isNull);
      expect(routes.match('nope', direction: 1), isNull);
    });

    test('picks the direction whose stops the API already reported', () {
      final routes = parseGtfsRoutes(text);

      final match = routes.match('8600-10', direction: 1, hintStopIds: {202, 203});

      expect(match?.directionId, 1);
      expect(match?.stopIds, [201, 202, 203]);
      expect(match?.shape, hasLength(2));
    });

    test('falls back to the sl convention without hints', () {
      final routes = parseGtfsRoutes(text);

      expect(routes.match('8600-10', direction: 1)?.directionId, 0);
      expect(routes.match('8600-10', direction: 2)?.directionId, 1);
      expect(routes.match('8600-10', direction: 2, hintStopIds: {999})?.directionId, 1);
    });
  });
}

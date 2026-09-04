import 'package:alive_eye/models/bus_stop.dart';
import 'package:alive_eye/services/gtfs_stops.dart';
import 'package:alive_eye/services/line_route_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const gtfsStops =
      'stop_id,stop_name,stop_desc,stop_lat,stop_lon\n'
      '201,Alpha,,-23.50,-46.60\n'
      '202,Bravo,,-23.51,-46.61\n'
      '203,Charlie,,-23.52,-46.62\n'
      '101,Delta,,-23.40,-46.50\n'
      '102,Echo,,-23.41,-46.51\n';
  const routesAsset =
      '# alive_eye routes v1\n'
      '8600-10\t0\t101,102\t\n'
      '8600-10\t1\t201,202,203,999\t_p~iF~ps|U_ulLnnqC\n';

  Future<Map<int, BusStop>> stopsByCode() async =>
      {for (final stop in parseGtfsStops(gtfsStops)) stop.code: stop};

  test('resolves the full ordered stop list and the street shape', () async {
    final service = LineRouteService(
      stopsByCode: stopsByCode,
      routesLoader: () async => routesAsset,
    );

    final route = await service.resolve(
      signage: '8600-10',
      direction: 2,
      hintStopIds: {202},
    );

    expect(route, isNotNull);
    expect(route!.stops.map((s) => s.code), [201, 202, 203]);
    expect(route.stops.first.name, 'Alpha');
    expect(route.complete, isFalse);
    expect(route.shape, hasLength(2));
    expect(route.path, route.shape);
    expect(service.hasRoutes, isTrue);
  });

  test('falls back to stop positions when there is no shape', () async {
    final service = LineRouteService(
      stopsByCode: stopsByCode,
      routesLoader: () async => routesAsset,
    );

    final route = await service.resolve(signage: '8600-10', direction: 1);

    expect(route!.stops.map((s) => s.code), [101, 102]);
    expect(route.complete, isTrue);
    expect(route.path, [route.stops[0].position, route.stops[1].position]);
  });

  test('returns null without a bundled route asset', () async {
    final service = LineRouteService(
      stopsByCode: stopsByCode,
      routesLoader: () async => null,
    );

    expect(await service.resolve(signage: '8600-10', direction: 1), isNull);
    expect(service.hasRoutes, isFalse);
  });

  test('returns null for a line missing from the asset', () async {
    final service = LineRouteService(
      stopsByCode: stopsByCode,
      routesLoader: () async => routesAsset,
    );

    expect(await service.resolve(signage: '1234-10', direction: 1), isNull);
  });
}

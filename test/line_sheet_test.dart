import 'dart:convert';

import 'package:alive_eye/models/bus_stop.dart';
import 'package:alive_eye/models/stop_forecast.dart';
import 'package:alive_eye/models/vehicle_position.dart';
import 'package:alive_eye/services/gtfs_stops.dart';
import 'package:alive_eye/services/line_route_service.dart';
import 'package:alive_eye/services/olho_vivo_client.dart';
import 'package:alive_eye/widgets/line_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'fake_alerts.dart';

void main() {
  const mainStop = NearbyStop(
    stop: BusStop(code: 640000459, name: '', address: 'R X', position: LatLng(-23.482, -46.718)),
    distanceMeters: 50,
  );
  const line = LineForecast(
    signage: '8600-10',
    lineCode: 34200,
    direction: 2,
    destination: 'LGO. DO PAISSANDÚ',
    origin: 'TERM. PIRITUBA',
    vehicles: [],
  );

  const gtfsStops =
      'stop_id,stop_name,stop_desc,stop_lat,stop_lon\n'
      '640000459,Zanini,,-23.482,-46.718\n'
      '640000453,Acangapiranga,,-23.485,-46.715\n'
      '700016473,Anhanguera,,-23.523,-46.653\n'
      '999001,Extra One,,-23.500,-46.700\n'
      '999002,Extra Two,,-23.505,-46.690\n';

  const routesAsset =
      '# alive_eye routes v1\n'
      '8600-10\t0\t999001,999002\t\n'
      '8600-10\t1\t640000453,999001,640000459,999002,700016473\t\n';

  Map<String, Object?> vehicle(String p, double lat, double lng, [String? t]) => {
    'p': p,
    'a': true,
    'ta': '2026-09-03T18:14:50Z',
    'py': lat,
    'px': lng,
    't': ?t,
  };

  final stopForecastsFor = <String>[];

  final client = OlhoVivoClient(
    tokenProvider: () => 'tok',
    httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/Login/Autenticar')) {
        return http.Response('true', 200, headers: {'set-cookie': 'apiCredentials=s'});
      }
      if (request.url.path.endsWith('/Posicao/Linha')) {
        expect(request.url.queryParameters['codigoLinha'], '34200');
        return http.Response(
          jsonEncode({
            'hr': '15:14',
            'vs': [
              vehicle('11056', -23.482, -46.720),
              vehicle('11059', -23.486, -46.726),
              vehicle('11051', -23.520, -46.667),
            ],
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/Previsao/Parada')) {
        stopForecastsFor.add(request.url.queryParameters['codigoParada']!);
        return http.Response(
          jsonEncode({
            'hr': '15:14',
            'p': {
              'cp': int.parse(request.url.queryParameters['codigoParada']!),
              'np': 'ANY STOP',
              'py': -23.482,
              'px': -46.718,
              'l': [
                {
                  'c': '8600-10',
                  'cl': 34200,
                  'sl': 2,
                  'lt0': 'LGO. DO PAISSANDU',
                  'lt1': 'TERM. PIRITUBA',
                  'qv': 1,
                  'vs': [vehicle('11059', -23.486, -46.726, '15:20')],
                },
                {
                  'c': '9999-10',
                  'cl': 999,
                  'sl': 1,
                  'lt0': 'OTHER',
                  'lt1': 'OTHER',
                  'qv': 1,
                  'vs': [vehicle('70001', -23.400, -46.600, '15:16')],
                },
              ],
            },
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/Previsao/Linha')) {
        return http.Response(
          jsonEncode({
            'hr': '15:14',
            'ps': [
              {
                'cp': 640000459,
                'np': '',
                'py': -23.482,
                'px': -46.718,
                'vs': [vehicle('11059', -23.486, -46.726, '15:20')],
              },
              {
                'cp': 640000453,
                'np': 'ACANGAPIRANGA C/B',
                'py': -23.485,
                'px': -46.715,
                'vs': [vehicle('11059', -23.486, -46.726, '15:17')],
              },
              {
                'cp': 700016473,
                'np': 'ANHANGUERA - C/B',
                'py': -23.523,
                'px': -46.653,
                'vs': [],
              },
            ],
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    }),
  );

  LineRouteService routeService(String? asset) => LineRouteService(
    stopsByCode: () async =>
        {for (final stop in parseGtfsStops(gtfsStops)) stop.code: stop},
    routesLoader: () async => asset,
  );

  Widget host(LineRouteService routes, {
    NearbyStop? stop,
    int? selectedPrefix,
    ValueChanged<LineSnapshot?>? onSnapshot,
    ValueChanged<VehiclePosition>? onVehicleTap,
  }) => MaterialApp(
    home: Scaffold(
      body: LineSheet(
        stop: stop ?? mainStop,
        line: line,
        selectedPrefix: selectedPrefix,
        client: client,
        routes: routes,
        alerts: fakeAlerts().alerts,
        scrollController: ScrollController(),
        onBack: () {},
        onClose: () {},
        onSnapshot: onSnapshot ?? (_) {},
        onVehicleTap: onVehicleTap ?? (_) {},
      ),
    ),
  );

  setUp(stopForecastsFor.clear);

  testWidgets('lists every bus of the line, ETA first, and reports the route', (tester) async {
    LineSnapshot? snapshot;
    VehiclePosition? tapped;
    await tester.pumpWidget(host(
      routeService(null),
      selectedPrefix: 11056,
      onSnapshot: (s) => snapshot = s,
      onVehicleTap: (v) => tapped = v,
    ));
    await tester.pumpAndSettle();

    expect(find.text('8600-10'), findsOneWidget);
    expect(find.text('→ LGO. DO PAISSANDÚ'), findsOneWidget);
    expect(find.textContaining('3 buses on this line'), findsOneWidget);
    expect(find.text('6 min'), findsOneWidget);
    expect(find.text('passed'), findsNWidgets(2));

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles, hasLength(3));
    expect(
      find.descendant(of: find.byWidget(tiles.first), matching: find.text('Bus 11059')),
      findsOneWidget,
    );

    expect(snapshot?.vehicles, hasLength(3));
    expect(snapshot?.path, hasLength(3));
    expect(snapshot?.stops.map((s) => s.code), containsAllInOrder([640000453, 640000459]));
    expect(snapshot?.etaByPrefix.keys, [11059]);
    expect(snapshot?.fromSchedule, isFalse);
    expect(find.textContaining('corridor stops only'), findsOneWidget);
    expect(stopForecastsFor, ['640000459']);

    await tester.tap(find.text('Bus 11051'));
    expect(tapped?.prefix, 11051);
  });

  testWidgets('shows arrivals for a stop the line forecast does not list', (tester) async {
    const gtfsOnlyStop = NearbyStop(
      stop: BusStop(code: 18848, name: 'Clínicas', address: '', position: LatLng(-23.554, -46.671)),
      distanceMeters: 30,
    );
    LineSnapshot? snapshot;
    await tester.pumpWidget(host(
      routeService(null),
      stop: gtfsOnlyStop,
      onSnapshot: (s) => snapshot = s,
    ));
    await tester.pumpAndSettle();

    expect(stopForecastsFor, ['18848']);
    expect(find.text('6 min'), findsOneWidget);
    expect(find.text('passed'), findsNWidgets(2));
    expect(find.text('no prediction'), findsNothing);
    expect(snapshot?.etaByPrefix.keys, [11059]);
  });

  testWidgets('labels buses as unpredicted when the stop has no forecast', (tester) async {
    final noForecast = OlhoVivoClient(
      tokenProvider: () => 'tok',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/Login/Autenticar')) {
          return http.Response('true', 200, headers: {'set-cookie': 'apiCredentials=s'});
        }
        if (request.url.path.endsWith('/Posicao/Linha')) {
          return http.Response(
            jsonEncode({'hr': '15:14', 'vs': [vehicle('11056', -23.482, -46.720)]}),
            200,
          );
        }
        return http.Response(jsonEncode({'hr': '15:14', 'p': null}), 200);
      }),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LineSheet(
          stop: mainStop,
          line: line,
          selectedPrefix: null,
          client: noForecast,
          routes: routeService(null),
          alerts: fakeAlerts().alerts,
          scrollController: ScrollController(),
          onBack: () {},
          onClose: () {},
          onSnapshot: (_) {},
          onVehicleTap: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('no prediction'), findsOneWidget);
    expect(find.text('passed'), findsNothing);
  });

  testWidgets('draws the full scheduled route when the GTFS asset is present', (tester) async {
    LineSnapshot? snapshot;
    await tester.pumpWidget(host(
      routeService(routesAsset),
      onSnapshot: (s) => snapshot = s,
    ));
    await tester.pumpAndSettle();

    expect(snapshot?.fromSchedule, isTrue);
    expect(
      snapshot?.stops.map((s) => s.code),
      [640000453, 999001, 640000459, 999002, 700016473],
    );
    expect(snapshot?.path, hasLength(5));
    expect(find.textContaining('5 stops'), findsOneWidget);
    expect(find.textContaining('corridor stops only'), findsNothing);
  });
}

import 'dart:convert';

import 'package:alive_eye/models/bus_stop.dart';
import 'package:alive_eye/models/stop_forecast.dart';
import 'package:alive_eye/services/arrival_alerts.dart';
import 'package:alive_eye/services/olho_vivo_client.dart';
import 'package:alive_eye/services/schedule_service.dart';
import 'package:alive_eye/widgets/stop_arrivals_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'fake_alerts.dart';

void main() {
  const stop = NearbyStop(
    stop: BusStop(
      code: 340015333,
      name: 'PARADA ROSA E SILVA B/C',
      address: 'R ROSA E SILVA/ R JOSE MARIA WHITAKER',
      position: LatLng(-23.5, -46.6),
    ),
    distanceMeters: 120,
  );

  final twoLines = <String, List<Map<String, dynamic>>>{
    'l': [
      {
        'c': '8000-10',
        'cl': 1,
        'sl': 1,
        'lt0': 'TERM. PINHEIROS',
        'vs': [
          {'p': 11111, 't': '10:08', 'a': false, 'py': -23.5, 'px': -46.6},
        ],
      },
      {
        'c': '701U-10',
        'cl': 2,
        'sl': 1,
        'lt0': 'METRO SANTANA',
        'vs': [
          {'p': 22222, 't': '10:01', 'a': false, 'py': -23.5, 'px': -46.6},
        ],
      },
    ],
  };

  // 9008-10 runs all day every day; N123-11 serves the stop but no day of the
  // week, which keeps both labels independent of when the test runs.
  const schedules =
      '# alive_eye schedules v1\n'
      '9008-10\t0\tTerm. Pirituba\t1111111\t340015333:0\t0-1439:720\n'
      'N123-11\t0\tTerm. Lapa\t0000000\t340015333:0\t0-1439:1800\n';

  OlhoVivoClient clientWith(Object? stopPayload) => OlhoVivoClient(
    tokenProvider: () => 'tok',
    httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/Login/Autenticar')) {
        return http.Response('true', 200, headers: {'set-cookie': 'apiCredentials=s'});
      }
      return http.Response(jsonEncode({'hr': '10:00', 'p': stopPayload}), 200);
    }),
  );

  Widget host(
    OlhoVivoClient client, {
    ValueChanged<StopForecast?>? onForecast,
    VehicleTapCallback? onVehicleTap,
    ArrivalAlerts? alerts,
    String? schedulesAsset,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: StopArrivalsSheet(
          stop: stop,
          client: client,
          alerts: alerts ?? fakeAlerts(client: client).alerts,
          schedules: ScheduleService(schedulesLoader: () async => schedulesAsset),
          scrollController: ScrollController(),
          onClose: () {},
          onForecastChanged: onForecast ?? (_) {},
          onVehicleTap: onVehicleTap ?? (_, _) {},
        ),
      ),
    );
  }

  testWidgets('lists incoming buses grouped by line with ETAs', (tester) async {
    StopForecast? reported;
    (LineForecast, VehicleForecast)? tapped;
    await tester.pumpWidget(
      host(
        onVehicleTap: (line, vehicle) => tapped = (line, vehicle),
        clientWith({
          'cp': 340015333,
          'np': 'PARADA ROSA E SILVA B/C',
          'py': -23.5,
          'px': -46.6,
          'l': [
            {
              'c': '8000-10',
              'cl': 1,
              'sl': 1,
              'lt0': 'TERM. PINHEIROS',
              'lt1': 'PCA. RAMOS DE AZEVEDO',
              'qv': 2,
              'vs': [
                {'p': 11111, 't': '10:00', 'a': true, 'ta': '', 'py': -23.5, 'px': -46.6},
                {'p': 22222, 't': '10:09', 'a': false, 'ta': '', 'py': -23.5, 'px': -46.6},
              ],
            },
          ],
        }),
        onForecast: (f) => reported = f,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PARADA ROSA E SILVA B/C'), findsOneWidget);
    expect(find.text('8000-10'), findsOneWidget);
    expect(find.text('→ TERM. PINHEIROS'), findsOneWidget);
    expect(find.text('Bus 11111'), findsOneWidget);
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('9 min'), findsOneWidget);
    expect(find.byIcon(Icons.accessible), findsOneWidget);
    expect(find.textContaining('Updated at 10:00'), findsOneWidget);
    expect(reported?.vehicles, hasLength(2));

    await tester.tap(find.text('Bus 22222'));
    expect(tapped?.$1.signage, '8000-10');
    expect(tapped?.$2.prefix, 22222);
  });

  testWidgets('shows an empty state when nothing is coming', (tester) async {
    await tester.pumpWidget(host(clientWith(null)));
    await tester.pumpAndSettle();

    expect(find.text('No buses heading to this stop right now.'), findsOneWidget);
  });

  testWidgets('each line card has its own alert bell', (tester) async {
    final client = clientWith({
      'cp': 340015333,
      'np': 'PARADA ROSA E SILVA B/C',
      'py': -23.5,
      'px': -46.6,
      ...twoLines,
    });
    final (:alerts, :notifier, :store) = fakeAlerts(client: client);
    await tester.pumpWidget(host(client, alerts: alerts));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.notifications_none), findsNWidgets(3));

    await tester.tap(find.byIcon(Icons.notifications_none).last);
    await tester.pumpAndSettle();

    expect(
      alerts.watchesLine(stop.stop.code, lineCode: 1, signage: '8000-10'),
      isTrue,
    );
    expect(
      alerts.watchesLine(stop.stop.code, lineCode: 2, signage: '701U-10'),
      isFalse,
    );
    expect(alerts.watchesEveryLine(stop.stop.code), isFalse);
    expect(find.textContaining('notified when 8000-10 is 3 min'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active), findsOneWidget);

    await _clearSnackBar(tester);
    await tester.tap(find.byIcon(Icons.notifications_active));
    await tester.pumpAndSettle();

    expect(alerts.watchesStop(stop.stop.code), isFalse);
    expect(find.textContaining('Arrival alerts off for 8000-10'), findsOneWidget);
  });

  testWidgets('the header bell watches every line at the stop', (tester) async {
    final client = clientWith({
      'cp': 340015333,
      'np': 'PARADA ROSA E SILVA B/C',
      'py': -23.5,
      'px': -46.6,
      ...twoLines,
    });
    final (:alerts, :notifier, :store) = fakeAlerts(client: client);
    await tester.pumpWidget(host(client, alerts: alerts));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.notifications_none).first);
    await tester.pumpAndSettle();

    expect(alerts.watchesEveryLine(stop.stop.code), isTrue);
    expect(find.byIcon(Icons.notifications_active), findsNWidgets(3));

    await _clearSnackBar(tester);
    await tester.tap(find.byIcon(Icons.notifications_active).last);
    await tester.pumpAndSettle();

    expect(find.text('Every line at this stop is already watched.'), findsOneWidget);
    expect(alerts.watchesEveryLine(stop.stop.code), isTrue);

    await _clearSnackBar(tester);
    await tester.tap(find.byIcon(Icons.notifications_active).first);
    await tester.pumpAndSettle();

    expect(alerts.watchesStop(stop.stop.code), isFalse);
  });

  testWidgets('a watched line notifies from the forecast the sheet polls', (tester) async {
    final client = clientWith({
      'cp': 340015333,
      'np': 'PARADA ROSA E SILVA B/C',
      'py': -23.5,
      'px': -46.6,
      ...twoLines,
    });
    final (:alerts, :notifier, :store) = fakeAlerts(client: client);
    await alerts.toggleLine(stop.stop, lineCode: 2, signage: '701U-10');

    await tester.pumpWidget(host(client, alerts: alerts));
    await tester.pumpAndSettle();

    expect(notifier.shown.single.$2, '701U-10 in 1 min');

    await alerts.toggleLine(stop.stop, lineCode: 2, signage: '701U-10');
  });

  testWidgets('lists timetable lines that have no bus reporting in', (tester) async {
    final client = clientWith(null);
    await tester.pumpWidget(host(client, schedulesAsset: schedules));
    await tester.pumpAndSettle();

    expect(find.textContaining('No bus is being tracked right now'), findsOneWidget);
    expect(find.text('9008-10'), findsOneWidget);
    expect(find.text('N123-11'), findsOneWidget);
    expect(find.textContaining('Term. Pirituba'), findsOneWidget);
    expect(find.textContaining('about every 12 min'), findsOneWidget);
    expect(find.textContaining('does not run today'), findsOneWidget);
  });

  testWidgets('keeps a line out of the timetable list once it is live', (tester) async {
    final client = clientWith({
      'cp': 340015333,
      'np': 'PARADA ROSA E SILVA B/C',
      'py': -23.5,
      'px': -46.6,
      'l': [
        {
          'c': '9008-10',
          'cl': 7,
          'sl': 1,
          'lt0': 'TERM. PIRITUBA',
          'vs': [
            {'p': 55555, 't': '10:04', 'a': false, 'py': -23.5, 'px': -46.6},
          ],
        },
      ],
    });
    await tester.pumpWidget(host(client, schedulesAsset: schedules));
    await tester.pumpAndSettle();

    expect(find.text('9008-10'), findsOneWidget);
    expect(find.text('4 min'), findsOneWidget);
    expect(find.textContaining('Also on the timetable here'), findsOneWidget);
    expect(find.textContaining('about every 12 min'), findsNothing);
  });

  testWidgets('a timetable line can be watched by its bell', (tester) async {
    final client = clientWith(null);
    final (:alerts, :notifier, :store) = fakeAlerts(client: client);
    await tester.pumpWidget(host(client, alerts: alerts, schedulesAsset: schedules));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.notifications_none).at(1));
    await tester.pumpAndSettle();

    expect(
      alerts.watchesLine(stop.stop.code, lineCode: 7, signage: '9008-10'),
      isTrue,
    );
    expect(store.saved.single.lineSignage, '9008-10');

    await _clearSnackBar(tester);
    await tester.tap(find.byIcon(Icons.notifications_active));
    await tester.pumpAndSettle();
    expect(alerts.watchesStop(stop.stop.code), isFalse);
  });
}

Future<void> _clearSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

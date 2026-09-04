import 'dart:convert';

import 'package:alive_eye/models/bus_stop.dart';
import 'package:alive_eye/models/stop_forecast.dart';
import 'package:alive_eye/services/alert_store.dart';
import 'package:alive_eye/services/olho_vivo_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'fake_alerts.dart';

void main() {
  const stop = BusStop(
    code: 340015333,
    name: 'PARADA ROSA E SILVA B/C',
    address: 'R ROSA E SILVA',
    position: LatLng(-23.5, -46.6),
  );

  Map<String, dynamic> bus(int prefix, String arrival) => {
    'p': prefix,
    't': arrival,
    'a': false,
    'py': -23.5,
    'px': -46.6,
  };

  Map<String, dynamic> lineJson(
    String signage,
    int lineCode,
    String destination,
    List<Map<String, dynamic>> vehicles,
  ) => {
    'c': signage,
    'cl': lineCode,
    'sl': 1,
    'lt0': destination,
    'vs': vehicles,
  };

  StopForecast forecastWith(List<Map<String, dynamic>> lines) =>
      StopForecast.fromJson({
        'hr': '10:00',
        'p': {
          'cp': stop.code,
          'np': stop.name,
          'py': -23.5,
          'px': -46.6,
          'l': lines,
        },
      })!;

  final twoLines = forecastWith([
    lineJson('8000-10', 1, 'TERM. PINHEIROS', [bus(11111, '10:02')]),
    lineJson('701U-10', 2, 'METRO SANTANA', [bus(22222, '10:01')]),
  ]);

  test('watching one line ignores the other lines at the same stop', () async {
    final (:alerts, :notifier, :store) = fakeAlerts();

    await alerts.toggleLine(stop, lineCode: 1, signage: '8000-10');
    await alerts.consider(twoLines);

    expect(notifier.shown.single.$2, '8000-10 in 2 min');
    expect(alerts.watchesLine(stop.code, lineCode: 1, signage: '8000-10'), isTrue);
    expect(alerts.watchesLine(stop.code, lineCode: 2, signage: '701U-10'), isFalse);
    expect(alerts.watchesEveryLine(stop.code), isFalse);
    expect(alerts.watchesStop(stop.code), isTrue);
  });

  test('watching every line notifies for all of them', () async {
    final (:alerts, :notifier, :store) = fakeAlerts();

    await alerts.toggleEveryLine(stop);
    await alerts.consider(twoLines);

    expect(notifier.shown.map((shown) => shown.$2), [
      '701U-10 in 1 min',
      '8000-10 in 2 min',
    ]);
    expect(alerts.watchesLine(stop.code, lineCode: 2, signage: '701U-10'), isTrue);
  });

  test('lines can be watched independently and dropped one at a time', () async {
    final (:alerts, :notifier, :store) = fakeAlerts();

    await alerts.toggleLine(stop, lineCode: 1, signage: '8000-10');
    await alerts.toggleLine(stop, lineCode: 2, signage: '701U-10');
    expect(store.saved, hasLength(2));

    expect(await alerts.toggleLine(stop, lineCode: 1, signage: '8000-10'), isFalse);
    expect(alerts.watchesLine(stop.code, lineCode: 1, signage: '8000-10'), isFalse);
    expect(alerts.watchesLine(stop.code, lineCode: 2, signage: '701U-10'), isTrue);
    expect(store.saved.single.lineSignage, '701U-10');
  });

  test('watching every line replaces the per-line alerts at that stop', () async {
    final (:alerts, :notifier, :store) = fakeAlerts();

    await alerts.toggleLine(stop, lineCode: 1, signage: '8000-10');
    await alerts.toggleEveryLine(stop);

    expect(alerts.targets, hasLength(1));
    expect(store.saved.single.isEveryLine, isTrue);
  });

  test('a timetable-only line is watched by signage until it goes live', () async {
    final (:alerts, :notifier, :store) = fakeAlerts();

    await alerts.toggleLine(
      stop,
      lineCode: AlertTarget.bySignage,
      signage: '8000-10',
    );

    expect(
      alerts.watchesLine(stop.code, lineCode: 1, signage: '8000-10'),
      isTrue,
      reason: 'the live card for the same line must read as watched',
    );
    expect(alerts.watchesLine(stop.code, lineCode: 2, signage: '701U-10'), isFalse);

    await alerts.consider(twoLines);
    expect(notifier.shown.single.$2, '8000-10 in 2 min');
  });

  test('the live bell turns off an alert armed from the timetable', () async {
    final (:alerts, :notifier, :store) = fakeAlerts();
    await alerts.toggleLine(
      stop,
      lineCode: AlertTarget.bySignage,
      signage: '8000-10',
    );

    expect(await alerts.toggleLine(stop, lineCode: 1, signage: '8000-10'), isFalse);
    expect(alerts.watchesStop(stop.code), isFalse);
    expect(store.saved, isEmpty);
  });

  test('a bus already announced is not announced again', () async {
    final (:alerts, :notifier, :store) = fakeAlerts();

    await alerts.toggleLine(stop, lineCode: 1, signage: '8000-10');
    await alerts.consider(twoLines);
    await alerts.consider(twoLines);

    expect(notifier.shown, hasLength(1));
  });

  test('does not arm when notifications are denied', () async {
    final (:alerts, :notifier, :store) = fakeAlerts(allowed: false);

    expect(await alerts.toggleLine(stop, lineCode: 1, signage: '8000-10'), isFalse);
    expect(alerts.watchesStop(stop.code), isFalse);
    expect(store.saved, isEmpty);
  });

  test('persists and restores the stop, the line and their labels', () async {
    final (:alerts, :notifier, :store) = fakeAlerts();
    await alerts.toggleLine(stop, lineCode: 1, signage: '8000-10');

    final saved = store.saved.single;
    expect(saved.stopCode, stop.code);
    expect(saved.stopName, stop.name);
    expect(saved.lineCode, 1);
    expect(saved.lineSignage, '8000-10');

    final restored = fakeAlerts();
    restored.store.saved = [saved];
    await restored.alerts.restore();

    expect(restored.alerts.watchesLine(stop.code, lineCode: 1, signage: '8000-10'), isTrue);
    expect(restored.alerts.watchesLine(stop.code, lineCode: 2, signage: '701U-10'), isFalse);
  });

  test('says a bus is arriving when it is due now', () async {
    final (:alerts, :notifier, :store) = fakeAlerts();
    await alerts.toggleEveryLine(stop);

    await alerts.consider(
      forecastWith([
        lineJson('8000-10', 1, 'TERM. PINHEIROS', [bus(11111, '10:00')]),
      ]),
    );

    expect(notifier.shown.single.$2, '8000-10 is arriving');
    expect(notifier.shown.single.$3, 'PARADA ROSA E SILVA B/C → TERM. PINHEIROS');
  });

  test('ignores buses that are still far away', () async {
    final (:alerts, :notifier, :store) = fakeAlerts();
    await alerts.toggleEveryLine(stop);

    await alerts.consider(
      forecastWith([
        lineJson('8000-10', 1, 'TERM. PINHEIROS', [bus(11111, '10:20')]),
      ]),
    );

    expect(notifier.shown, isEmpty);
  });

  test('notifies again after a bus has left and the prefix comes back', () async {
    final (:alerts, :notifier, :store) = fakeAlerts();
    await alerts.toggleEveryLine(stop);

    final near = forecastWith([
      lineJson('8000-10', 1, 'TERM. PINHEIROS', [bus(11111, '10:01')]),
    ]);
    await alerts.consider(near);
    await alerts.consider(forecastWith([]));
    await alerts.consider(near);

    expect(notifier.shown, hasLength(2));
  });

  test('ignores forecasts for stops that are not watched', () async {
    final (:alerts, :notifier, :store) = fakeAlerts();

    await alerts.consider(twoLines);

    expect(notifier.shown, isEmpty);
  });

  test('polls every watched stop and notifies from the response', () async {
    final (:alerts, :notifier, :store) = fakeAlerts(
      client: OlhoVivoClient(
        tokenProvider: () => 'tok',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/Login/Autenticar')) {
            return http.Response(
              'true',
              200,
              headers: {'set-cookie': 'apiCredentials=s'},
            );
          }
          return http.Response(
            jsonEncode({
              'hr': '10:00',
              'p': {
                'cp': stop.code,
                'np': stop.name,
                'py': -23.5,
                'px': -46.6,
                'l': [
                  lineJson('8000-10', 1, 'TERM. PINHEIROS', [bus(33333, '10:03')]),
                  lineJson('701U-10', 2, 'METRO SANTANA', [bus(44444, '10:00')]),
                ],
              },
            }),
            200,
          );
        }),
      ),
    );

    await alerts.toggleLine(stop, lineCode: 1, signage: '8000-10');
    await alerts.poll();

    expect(notifier.shown.single.$2, '8000-10 in 3 min');
  });
}

import 'package:alive_eye/models/bus_stop.dart';
import 'package:alive_eye/models/line_stops_forecast.dart';
import 'package:alive_eye/models/stop_forecast.dart';
import 'package:alive_eye/services/route_path.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

LineStopForecast stop(int code, double lng, Map<int, int> etas) => LineStopForecast(
  stop: BusStop(code: code, name: 'S$code', address: '', position: LatLng(-23.5, lng)),
  vehicles: [
    for (final MapEntry(key: prefix, value: eta) in etas.entries)
      VehicleForecast(
        prefix: prefix,
        accessible: false,
        reportedAt: null,
        position: const LatLng(0, 0),
        arrivalTime: '',
        etaMinutes: eta,
      ),
  ],
);

List<int> codes(List<LineStopForecast> stops) => [for (final s in stops) s.stop.code];

void main() {
  test('orders stops by the arrival times of the buses', () {
    final stops = [
      stop(3, -46.63, {1: 12, 2: 3}),
      stop(1, -46.61, {1: 4}),
      stop(4, -46.64, {2: 7}),
      stop(2, -46.62, {1: 8}),
    ];

    expect(codes(orderLineStops(stops)), [1, 2, 3, 4]);
  });

  test('fits stops without predictions into the route geometrically', () {
    final stops = [
      stop(5, -46.65, {}),
      stop(2, -46.62, {1: 5}),
      stop(0, -46.60, {}),
      stop(3, -46.63, {1: 9}),
      stop(1, -46.61, {1: 2}),
      stop(4, -46.64, {}),
    ];

    expect(codes(orderLineStops(stops)), [0, 1, 2, 3, 4, 5]);
  });

  test('tolerates equal arrival minutes and contradicting buses', () {
    final stops = [
      stop(1, -46.61, {1: 2, 2: 9}),
      stop(2, -46.62, {1: 2, 2: 5}),
      stop(3, -46.63, {1: 6, 2: 5}),
    ];

    final ordered = codes(orderLineStops(stops));

    expect(ordered, hasLength(3));
    expect(ordered.toSet(), {1, 2, 3});
  });

  test('chains stops by proximity when nobody is predicted', () {
    final stops = [
      stop(2, -46.62, {}),
      stop(4, -46.64, {}),
      stop(1, -46.61, {}),
      stop(3, -46.63, {}),
    ];

    final ordered = codes(orderLineStops(stops));

    expect(ordered, anyOf([equals([1, 2, 3, 4]), equals([4, 3, 2, 1])]));
  });

  test('keeps tiny lists as they are', () {
    final stops = [stop(1, -46.61, {}), stop(2, -46.62, {})];

    expect(codes(orderLineStops(stops)), [1, 2]);
  });
}

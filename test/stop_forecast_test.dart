import 'package:alive_eye/models/stop_forecast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VehicleForecast.etaBetween', () {
    test('counts minutes until arrival', () {
      expect(VehicleForecast.etaBetween('14:30', '14:42'), 12);
    });

    test('clamps arrivals in the past to zero', () {
      expect(VehicleForecast.etaBetween('14:30', '14:28'), 0);
    });

    test('handles forecasts that cross midnight', () {
      expect(VehicleForecast.etaBetween('23:58', '00:03'), 5);
    });

    test('falls back to zero on malformed times', () {
      expect(VehicleForecast.etaBetween('', '10:00'), 0);
      expect(VehicleForecast.etaBetween('10:00', 'xx:yy'), 0);
    });
  });

  group('StopForecast.fromJson', () {
    test('returns null when the API has no stop data', () {
      expect(StopForecast.fromJson({'hr': '10:00', 'p': null}), isNull);
    });

    test('sorts lines and vehicles by soonest arrival', () {
      final forecast = StopForecast.fromJson({
        'hr': '10:00',
        'p': {
          'cp': 1,
          'np': 'X',
          'py': 0,
          'px': 0,
          'l': [
            {
              'c': 'B',
              'cl': 2,
              'sl': 1,
              'lt0': '',
              'lt1': '',
              'qv': 2,
              'vs': [
                {'p': 1, 't': '10:20', 'a': false, 'ta': '', 'py': 0, 'px': 0},
                {'p': 2, 't': '10:05', 'a': false, 'ta': '', 'py': 0, 'px': 0},
              ],
            },
            {
              'c': 'A',
              'cl': 1,
              'sl': 1,
              'lt0': '',
              'lt1': '',
              'qv': 1,
              'vs': [
                {'p': 3, 't': '10:02', 'a': false, 'ta': '', 'py': 0, 'px': 0},
              ],
            },
          ],
        },
      })!;

      expect(forecast.lines.map((l) => l.signage), ['A', 'B']);
      expect(forecast.lines[1].vehicles.map((v) => v.prefix), [2, 1]);
      expect(forecast.lines[1].vehicles.first.etaMinutes, 5);
      expect(forecast.vehicles, hasLength(3));
    });
  });
}

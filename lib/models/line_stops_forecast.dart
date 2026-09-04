import 'package:latlong2/latlong.dart';

import 'bus_stop.dart';
import 'json_utils.dart';
import 'stop_forecast.dart';

class LineStopsForecast {
  const LineStopsForecast({required this.referenceTime, required this.stops});

  factory LineStopsForecast.fromJson(Map<String, dynamic> json) {
    final referenceTime = json['hr'] as String? ?? '';
    return LineStopsForecast(
      referenceTime: referenceTime,
      stops: [
        for (final s in json['ps'] as List? ?? const [])
          LineStopForecast.fromJson(s as Map<String, dynamic>, referenceTime),
      ],
    );
  }

  final String referenceTime;
  final List<LineStopForecast> stops;

  LineStopForecast? stopByCode(int code) {
    for (final s in stops) {
      if (s.stop.code == code) return s;
    }
    return null;
  }
}

class LineStopForecast {
  const LineStopForecast({required this.stop, required this.vehicles});

  factory LineStopForecast.fromJson(Map<String, dynamic> json, String referenceTime) {
    return LineStopForecast(
      stop: BusStop(
        code: asInt(json['cp']),
        name: (json['np'] as String? ?? '').trim(),
        address: '',
        position: LatLng(
          (json['py'] as num).toDouble(),
          (json['px'] as num).toDouble(),
        ),
      ),
      vehicles: parseVehicleForecasts(json['vs'], referenceTime),
    );
  }

  final BusStop stop;
  final List<VehicleForecast> vehicles;
}

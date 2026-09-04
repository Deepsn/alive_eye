import 'json_utils.dart';
import 'vehicle_position.dart';

class StopForecast {
  const StopForecast({
    required this.referenceTime,
    required this.stopCode,
    required this.lines,
  });

  static StopForecast? fromJson(Map<String, dynamic> json) {
    final stop = json['p'];
    if (stop is! Map<String, dynamic>) return null;

    final referenceTime = json['hr'] as String? ?? '';
    final lines = [
      for (final line in stop['l'] as List? ?? const [])
        LineForecast.fromJson(line as Map<String, dynamic>, referenceTime),
    ]..sort((a, b) => (a.soonestEta ?? 1 << 30).compareTo(b.soonestEta ?? 1 << 30));

    return StopForecast(
      referenceTime: referenceTime,
      stopCode: asInt(stop['cp']),
      lines: lines,
    );
  }

  final String referenceTime;
  final int stopCode;
  final List<LineForecast> lines;

  Iterable<VehicleForecast> get vehicles => lines.expand((l) => l.vehicles);
}

class LineForecast {
  const LineForecast({
    required this.signage,
    required this.lineCode,
    required this.direction,
    required this.destination,
    required this.origin,
    required this.vehicles,
  });

  factory LineForecast.fromJson(Map<String, dynamic> json, String referenceTime) {
    return LineForecast(
      signage: json['c'] as String? ?? '',
      lineCode: asInt(json['cl']),
      direction: asInt(json['sl']),
      destination: (json['lt0'] as String? ?? '').trim(),
      origin: (json['lt1'] as String? ?? '').trim(),
      vehicles: parseVehicleForecasts(json['vs'], referenceTime),
    );
  }

  final String signage;
  final int lineCode;
  final int direction;
  final String destination;
  final String origin;
  final List<VehicleForecast> vehicles;

  int? get soonestEta => vehicles.isEmpty ? null : vehicles.first.etaMinutes;
}

class VehicleForecast extends VehiclePosition {
  const VehicleForecast({
    required super.prefix,
    required super.accessible,
    required super.reportedAt,
    required super.position,
    required this.arrivalTime,
    required this.etaMinutes,
  });

  factory VehicleForecast.fromJson(Map<String, dynamic> json, String referenceTime) {
    final base = VehiclePosition.fromJson(json);
    final arrivalTime = json['t'] as String? ?? '';
    return VehicleForecast(
      prefix: base.prefix,
      accessible: base.accessible,
      reportedAt: base.reportedAt,
      position: base.position,
      arrivalTime: arrivalTime,
      etaMinutes: etaBetween(referenceTime, arrivalTime),
    );
  }

  final String arrivalTime;
  final int etaMinutes;

  String get etaLabel => etaMinutes == 0 ? 'Now' : '$etaMinutes min';

  static int etaBetween(String reference, String arrival) {
    final from = _minutesOfDay(reference);
    final to = _minutesOfDay(arrival);
    if (from == null || to == null) return 0;
    var diff = to - from;
    if (diff < -12 * 60) diff += 24 * 60;
    return diff < 0 ? 0 : diff;
  }

  static int? _minutesOfDay(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }
}

List<VehicleForecast> parseVehicleForecasts(Object? json, String referenceTime) => [
  for (final v in json as List? ?? const [])
    VehicleForecast.fromJson(v as Map<String, dynamic>, referenceTime),
]..sort((a, b) => a.etaMinutes.compareTo(b.etaMinutes));

import 'package:latlong2/latlong.dart';

import 'json_utils.dart';

class VehiclePosition {
  const VehiclePosition({
    required this.prefix,
    required this.accessible,
    required this.reportedAt,
    required this.position,
  });

  factory VehiclePosition.fromJson(Map<String, dynamic> json) => VehiclePosition(
    prefix: asInt(json['p']),
    accessible: json['a'] as bool? ?? false,
    reportedAt: DateTime.tryParse(json['ta'] as String? ?? ''),
    position: LatLng(
      (json['py'] as num).toDouble(),
      (json['px'] as num).toDouble(),
    ),
  );

  final int prefix;
  final bool accessible;
  final DateTime? reportedAt;
  final LatLng position;
}

class LinePositions {
  const LinePositions({required this.referenceTime, required this.vehicles});

  factory LinePositions.fromJson(Map<String, dynamic> json) => LinePositions(
    referenceTime: json['hr'] as String? ?? '',
    vehicles: [
      for (final v in json['vs'] as List? ?? const [])
        VehiclePosition.fromJson(v as Map<String, dynamic>),
    ],
  );

  final String referenceTime;
  final List<VehiclePosition> vehicles;
}

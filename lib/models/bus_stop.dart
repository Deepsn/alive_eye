import 'package:latlong2/latlong.dart';

class BusStop {
  const BusStop({
    required this.code,
    required this.name,
    required this.address,
    required this.position,
  });

  factory BusStop.fromJson(Map<String, dynamic> json) => BusStop(
    code: (json['cp'] as num).toInt(),
    name: (json['np'] as String? ?? '').trim(),
    address: (json['ed'] as String? ?? '').trim(),
    position: LatLng(
      (json['py'] as num).toDouble(),
      (json['px'] as num).toDouble(),
    ),
  );

  final int code;
  final String name;
  final String address;
  final LatLng position;

  String get displayName => name.isNotEmpty ? name : address;

  @override
  bool operator ==(Object other) => other is BusStop && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

class NearbyStop {
  const NearbyStop({required this.stop, required this.distanceMeters});

  final BusStop stop;
  final double distanceMeters;

  String get distanceLabel => distanceMeters < 1000
      ? '${distanceMeters.round()} m'
      : '${(distanceMeters / 1000).toStringAsFixed(1)} km';
}

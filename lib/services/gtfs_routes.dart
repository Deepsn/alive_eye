import 'dart:convert';

import 'package:latlong2/latlong.dart';

class GtfsRoute {
  const GtfsRoute({
    required this.signage,
    required this.directionId,
    required this.stopIds,
    required this.shape,
  });

  final String signage;
  final int directionId;
  final List<int> stopIds;
  final List<LatLng> shape;
}

class GtfsRoutes {
  const GtfsRoutes(this._bySignage);

  static const empty = GtfsRoutes(<String, List<GtfsRoute>>{});

  final Map<String, List<GtfsRoute>> _bySignage;

  bool get isEmpty => _bySignage.isEmpty;

  int get length => _bySignage.values.fold(0, (sum, list) => sum + list.length);

  // Direction is taken from the stops SPTrans already reported for this line;
  // the sl -> direction_id convention is only the fallback.
  GtfsRoute? match(String signage, {required int direction, Set<int> hintStopIds = const {}}) {
    final candidates = _bySignage[signage];
    if (candidates == null || candidates.isEmpty) return null;

    if (hintStopIds.isNotEmpty) {
      GtfsRoute? best;
      var bestOverlap = 0;
      for (final candidate in candidates) {
        final overlap = candidate.stopIds.where(hintStopIds.contains).length;
        if (overlap > bestOverlap) {
          bestOverlap = overlap;
          best = candidate;
        }
      }
      if (best != null) return best;
    }

    final wanted = direction == 2 ? 1 : 0;
    for (final candidate in candidates) {
      if (candidate.directionId == wanted) return candidate;
    }
    return candidates.first;
  }
}

GtfsRoutes parseGtfsRoutes(String text) {
  final bySignage = <String, List<GtfsRoute>>{};
  for (final line in const LineSplitter().convert(text)) {
    if (line.isEmpty || line.startsWith('#')) continue;
    final parts = line.split('\t');
    if (parts.length < 3) continue;
    final signage = parts[0].trim();
    final direction = int.tryParse(parts[1].trim());
    if (signage.isEmpty || direction == null) continue;

    final stopIds = [
      for (final id in parts[2].split(',')) ?int.tryParse(id.trim()),
    ];
    if (stopIds.length < 2) continue;

    (bySignage[signage] ??= []).add(GtfsRoute(
      signage: signage,
      directionId: direction,
      stopIds: stopIds,
      shape: parts.length > 3 ? decodePolyline(parts[3]) : const [],
    ));
  }
  return GtfsRoutes(bySignage);
}

List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0;
  var lat = 0;
  var lng = 0;
  while (index < encoded.length) {
    final dLat = _decodeValue(encoded, index);
    if (dLat == null) break;
    index = dLat.$2;
    final dLng = _decodeValue(encoded, index);
    if (dLng == null) break;
    index = dLng.$2;
    lat += dLat.$1;
    lng += dLng.$1;
    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}

(int, int)? _decodeValue(String encoded, int start) {
  var index = start;
  var shift = 0;
  var result = 0;
  int byte;
  do {
    if (index >= encoded.length) return null;
    byte = encoded.codeUnitAt(index++) - 63;
    result |= (byte & 0x1f) << shift;
    shift += 5;
  } while (byte >= 0x20);
  return ((result & 1) != 0 ? ~(result >> 1) : result >> 1, index);
}

String encodePolyline(List<(double, double)> points) {
  final buffer = StringBuffer();
  var lastLat = 0;
  var lastLng = 0;
  for (final (lat, lng) in points) {
    final e5Lat = (lat * 1e5).round();
    final e5Lng = (lng * 1e5).round();
    _encodeValue(buffer, e5Lat - lastLat);
    _encodeValue(buffer, e5Lng - lastLng);
    lastLat = e5Lat;
    lastLng = e5Lng;
  }
  return buffer.toString();
}

void _encodeValue(StringBuffer buffer, int value) {
  var v = value < 0 ? ~(value << 1) : value << 1;
  while (v >= 0x20) {
    buffer.writeCharCode((0x20 | (v & 0x1f)) + 63);
    v >>= 5;
  }
  buffer.writeCharCode(v + 63);
}

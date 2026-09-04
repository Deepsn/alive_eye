import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../models/bus_stop.dart';
import 'csv.dart';

List<BusStop> parseGtfsStops(String csv) {
  final lines = const LineSplitter().convert(csv);
  if (lines.isEmpty) return const [];

  final header = csvHeader(lines.first);
  final id = header.indexOf('stop_id');
  final name = header.indexOf('stop_name');
  final desc = header.indexOf('stop_desc');
  final lat = header.indexOf('stop_lat');
  final lon = header.indexOf('stop_lon');
  if (id < 0 || lat < 0 || lon < 0) {
    throw const FormatException('stops.txt is missing stop_id/stop_lat/stop_lon columns');
  }
  final width = [id, name, desc, lat, lon].reduce((a, b) => a > b ? a : b) + 1;

  final stops = <BusStop>[];
  for (final line in lines.skip(1)) {
    if (line.trim().isEmpty) continue;
    final f = splitCsvLine(line);
    if (f.length < width) continue;
    final code = int.tryParse(f[id].trim());
    final latitude = double.tryParse(f[lat].trim());
    final longitude = double.tryParse(f[lon].trim());
    if (code == null || latitude == null || longitude == null) continue;
    stops.add(BusStop(
      code: code,
      name: name < 0 ? '' : f[name].trim(),
      address: desc < 0 ? '' : f[desc].trim(),
      position: LatLng(latitude, longitude),
    ));
  }
  return stops;
}

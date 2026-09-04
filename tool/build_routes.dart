// Preprocesses a SPTrans GTFS package into assets/gtfs/routes.txt and
// assets/gtfs/schedules.txt.
// Usage: dart run tool/build_routes.dart <gtfs-dir> [output-dir]
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:alive_eye/services/csv.dart';
import 'package:alive_eye/services/gtfs_routes.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('usage: dart run tool/build_routes.dart <gtfs-dir> [output]');
    exitCode = 64;
    return;
  }
  final dir = args[0];
  final outDir = args.length > 1 ? args[1] : 'assets/gtfs';
  final out = File('$outDir/routes.txt');
  final scheduleOut = File('$outDir/schedules.txt');

  final routeNames = <String, String>{};
  await _forEachRow('$dir/routes.txt', (row) {
    final id = row['route_id'];
    final name = row['route_short_name'];
    if (id != null && name != null && name.isNotEmpty) routeNames[id] = name;
  });
  print('routes: ${routeNames.length}');

  final serviceDays = <String, String>{};
  await _forEachRow('$dir/calendar.txt', (row) {
    final id = row['service_id'];
    if (id == null) return;
    serviceDays[id] = [
      for (final day in _weekdays) row[day] == '1' ? '1' : '0',
    ].join();
  });
  print('services: ${serviceDays.length}');

  final trips =
      <String, ({String signage, int direction, String? shape, String days, String headsign})>{};
  await _forEachRow('$dir/trips.txt', (row) {
    final tripId = row['trip_id'];
    final signage = routeNames[row['route_id']];
    if (tripId == null || signage == null) return;
    trips[tripId] = (
      signage: signage,
      direction: int.tryParse(row['direction_id'] ?? '0') ?? 0,
      shape: row['shape_id'],
      days: serviceDays[row['service_id']] ?? '1111111',
      headsign: (row['trip_headsign'] ?? '').trim(),
    );
  });
  print('trips: ${trips.length}');

  final stopCount = <String, int>{};
  await _forEachRow('$dir/stop_times.txt', (row) {
    final tripId = row['trip_id'];
    if (tripId != null) stopCount[tripId] = (stopCount[tripId] ?? 0) + 1;
  });

  final bestTrip = <String, String>{};
  for (final MapEntry(key: tripId, value: trip) in trips.entries) {
    final key = '${trip.signage}\t${trip.direction}';
    final current = bestTrip[key];
    if (current == null || (stopCount[tripId] ?? 0) > (stopCount[current] ?? 0)) {
      bestTrip[key] = tripId;
    }
  }
  final selected = bestTrip.values.toSet();
  print('line directions: ${bestTrip.length}');

  final sequences = <String, List<(int, int, int)>>{};
  await _forEachRow('$dir/stop_times.txt', (row) {
    final tripId = row['trip_id'];
    if (tripId == null || !selected.contains(tripId)) return;
    final stopId = int.tryParse(row['stop_id']?.trim() ?? '');
    final sequence = int.tryParse(row['stop_sequence']?.trim() ?? '');
    if (stopId == null || sequence == null) return;
    (sequences[tripId] ??= []).add((
      sequence,
      stopId,
      _minutesOfDay(row['arrival_time']) ?? 0,
    ));
  });

  final frequencies = <String, List<(int, int, int)>>{};
  await _forEachRow('$dir/frequencies.txt', (row) {
    final tripId = row['trip_id'];
    if (tripId == null || !selected.contains(tripId)) return;
    final start = _minutesOfDay(row['start_time']);
    final end = _minutesOfDay(row['end_time']);
    final headway = int.tryParse(row['headway_secs']?.trim() ?? '');
    if (start == null || end == null || headway == null || headway <= 0) return;
    (frequencies[tripId] ??= []).add((start, end, headway));
  });
  print('trips with frequencies: ${frequencies.length}');

  final shapePoints = <String, List<(int, double, double)>>{};
  final wantedShapes = {
    for (final tripId in selected)
      if (trips[tripId]?.shape case final s? when s.isNotEmpty) s,
  };
  if (wantedShapes.isNotEmpty && File('$dir/shapes.txt').existsSync()) {
    await _forEachRow('$dir/shapes.txt', (row) {
      final id = row['shape_id'];
      if (id == null || !wantedShapes.contains(id)) return;
      final seq = int.tryParse(row['shape_pt_sequence']?.trim() ?? '');
      final lat = double.tryParse(row['shape_pt_lat']?.trim() ?? '');
      final lon = double.tryParse(row['shape_pt_lon']?.trim() ?? '');
      if (seq == null || lat == null || lon == null) return;
      (shapePoints[id] ??= []).add((seq, lat, lon));
    });
  }
  print('shapes: ${shapePoints.length}');

  final buffer = StringBuffer('# alive_eye routes v1\n');
  final schedules = StringBuffer('# alive_eye schedules v1\n');
  var written = 0;
  var scheduled = 0;
  final keys = bestTrip.keys.toList()..sort();
  for (final key in keys) {
    final tripId = bestTrip[key]!;
    final stops = sequences[tripId];
    if (stops == null || stops.length < 2) continue;
    stops.sort((a, b) => a.$1.compareTo(b.$1));

    final shapeId = trips[tripId]?.shape;
    final points = shapeId == null ? null : shapePoints[shapeId];
    if (points != null) points.sort((a, b) => a.$1.compareTo(b.$1));
    final encoded = points == null
        ? ''
        : encodePolyline([for (final (_, lat, lon) in points) (lat, lon)]);

    buffer.writeln('$key\t${[for (final (_, id, _) in stops) id].join(',')}\t$encoded');
    written++;

    final trip = trips[tripId];
    final windows = frequencies[tripId];
    if (trip == null || windows == null || windows.isEmpty) continue;
    windows.sort((a, b) => a.$1.compareTo(b.$1));
    final departure = stops.first.$3;
    schedules.writeln([
      key,
      trip.headsign,
      trip.days,
      [for (final (_, id, at) in stops) '$id:${at - departure}'].join(','),
      [for (final (start, end, headway) in windows) '$start-$end:$headway'].join(','),
    ].join('\t'));
    scheduled++;
  }

  await out.parent.create(recursive: true);
  await out.writeAsString(buffer.toString());
  print('wrote ${out.path}: $written line directions, '
      '${(await out.length() / 1024).round()} KB');

  await scheduleOut.writeAsString(schedules.toString());
  print('wrote ${scheduleOut.path}: $scheduled line directions, '
      '${(await scheduleOut.length() / 1024).round()} KB');
}

const _weekdays = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

int? _minutesOfDay(String? hhmmss) {
  final parts = (hhmmss ?? '').trim().split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

Future<void> _forEachRow(String path, void Function(Map<String, String>) onRow) async {
  final file = File(path);
  if (!file.existsSync()) throw FileSystemException('missing GTFS file', path);

  List<String>? header;
  await for (final line in _csvLines(file)) {
    final fields = splitCsvLine(line);
    if (header == null) {
      header = csvHeader(line);
      continue;
    }
    if (fields.length < header.length) continue;
    onRow({for (var i = 0; i < header.length; i++) header[i]: fields[i]});
  }
}

// GTFS values may contain quoted newlines, so rows are reassembled by quote parity.
Stream<String> _csvLines(File file) async* {
  final pending = StringBuffer();
  var quotes = 0;
  await for (final line in file
      .openRead()
      .transform(const SystemEncoding().decoder)
      .transform(const LineSplitter())) {
    if (pending.isNotEmpty) pending.write('\n');
    pending.write(line);
    quotes += '"'.allMatches(line).length;
    if (quotes.isEven) {
      final row = pending.toString();
      pending.clear();
      quotes = 0;
      if (row.trim().isNotEmpty) yield row;
    }
  }
  if (pending.isNotEmpty) yield pending.toString();
}

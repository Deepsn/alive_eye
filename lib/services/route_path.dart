import 'package:latlong2/latlong.dart';

import '../models/line_stops_forecast.dart';

// Previsao/Linha lists stops alphabetically. Each bus's arrival times give the
// order of the stops still ahead of it; merging those orders recovers most of
// the route, and stops nobody is predicted for are slotted in geometrically.
List<LineStopForecast> orderLineStops(List<LineStopForecast> stops) {
  if (stops.length < 3) return List.of(stops);
  const distance = Distance();
  double d(LineStopForecast a, LineStopForecast b) => distance(a.stop.position, b.stop.position);

  final byVehicle = <int, List<(int, LineStopForecast)>>{};
  for (final stop in stops) {
    for (final v in stop.vehicles) {
      (byVehicle[v.prefix] ??= []).add((v.etaMinutes, stop));
    }
  }

  final successors = <LineStopForecast, Set<LineStopForecast>>{};
  final indegree = <LineStopForecast, int>{};
  for (final sequence in byVehicle.values) {
    sequence.sort((a, b) => a.$1.compareTo(b.$1));
    final groups = <List<LineStopForecast>>[];
    int? lastEta;
    for (final (eta, stop) in sequence) {
      if (eta != lastEta) groups.add([]);
      groups.last.add(stop);
      lastEta = eta;
    }
    for (var i = 0; i + 1 < groups.length; i++) {
      for (final a in groups[i]) {
        for (final b in groups[i + 1]) {
          indegree.putIfAbsent(a, () => 0);
          indegree.putIfAbsent(b, () => 0);
          if ((successors[a] ??= {}).add(b)) indegree[b] = indegree[b]! + 1;
        }
      }
    }
  }

  final ordered = <LineStopForecast>[];
  final remaining = indegree.keys.toSet();
  while (remaining.isNotEmpty) {
    final heads = remaining.where((s) => indegree[s] == 0).toList();
    final pool = heads.isNotEmpty ? heads : remaining.toList();
    final pick = ordered.isEmpty
        ? pool.reduce((a, b) => indegree[a]! <= indegree[b]! ? a : b)
        : pool.reduce((a, b) => d(ordered.last, a) <= d(ordered.last, b) ? a : b);
    ordered.add(pick);
    remaining.remove(pick);
    for (final next in successors[pick] ?? const <LineStopForecast>{}) {
      indegree[next] = indegree[next]! - 1;
    }
  }

  final unplaced = stops.where((s) => !indegree.containsKey(s)).toList();
  if (ordered.isEmpty && unplaced.isNotEmpty) {
    final lat = unplaced.map((s) => s.stop.position.latitude).reduce((a, b) => a + b) / unplaced.length;
    final lng = unplaced.map((s) => s.stop.position.longitude).reduce((a, b) => a + b) / unplaced.length;
    final centroid = LatLng(lat, lng);
    final seed = unplaced.reduce((a, b) =>
        distance(centroid, a.stop.position) >= distance(centroid, b.stop.position) ? a : b);
    ordered.add(seed);
    unplaced.remove(seed);
  }

  while (unplaced.isNotEmpty) {
    LineStopForecast? bestStop;
    var bestIndex = 0;
    var bestCost = double.infinity;
    for (final s in unplaced) {
      void consider(double cost, int index) {
        if (cost < bestCost) {
          bestCost = cost;
          bestStop = s;
          bestIndex = index;
        }
      }

      consider(d(s, ordered.first), 0);
      consider(d(ordered.last, s), ordered.length);
      for (var i = 0; i + 1 < ordered.length; i++) {
        consider(d(ordered[i], s) + d(s, ordered[i + 1]) - d(ordered[i], ordered[i + 1]), i + 1);
      }
    }
    ordered.insert(bestIndex, bestStop!);
    unplaced.remove(bestStop);
  }

  return ordered;
}

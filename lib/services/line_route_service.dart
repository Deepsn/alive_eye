import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';

import '../models/bus_stop.dart';
import 'gtfs_routes.dart';
import 'parse_off_thread.dart';
import 'stops_store.dart';

typedef StopLookup = Future<Map<int, BusStop>> Function();

class LineRoute {
  const LineRoute({required this.stops, required this.shape, required this.complete});

  final List<BusStop> stops;
  final List<LatLng> shape;
  final bool complete;

  List<LatLng> get path =>
      shape.length > 1 ? shape : [for (final stop in stops) stop.position];
}

class LineRouteService {
  LineRouteService({required this._stopsByCode, TextLoader? routesLoader})
    : _routesLoader = routesLoader ?? _loadBundledRoutes;

  static const routesAsset = 'assets/gtfs/routes.txt';

  final StopLookup _stopsByCode;
  final TextLoader _routesLoader;

  GtfsRoutes? _routes;
  Future<GtfsRoutes>? _loading;

  bool get isLoaded => _routes != null;

  bool get hasRoutes => _routes?.isEmpty == false;

  Future<GtfsRoutes> load() {
    final routes = _routes;
    if (routes != null) return Future.value(routes);
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<LineRoute?> resolve({
    required String signage,
    required int direction,
    Set<int> hintStopIds = const {},
  }) async {
    final route = (await load()).match(
      signage,
      direction: direction,
      hintStopIds: hintStopIds,
    );
    if (route == null) return null;

    final byCode = await _stopsByCode();
    final stops = [for (final id in route.stopIds) ?byCode[id]];
    if (stops.length < 2) return null;

    return LineRoute(
      stops: stops,
      shape: route.shape,
      complete: stops.length == route.stopIds.length,
    );
  }

  Future<GtfsRoutes> _load() async {
    GtfsRoutes parsed;
    try {
      final text = await _routesLoader();
      parsed = text == null || text.isEmpty
          ? GtfsRoutes.empty
          : await parseOffThread(text, parseGtfsRoutes);
    } catch (_) {
      parsed = GtfsRoutes.empty;
    }
    _routes = parsed;
    return parsed;
  }

  static Future<String?> _loadBundledRoutes() async {
    try {
      return await rootBundle.loadString(routesAsset);
    } catch (_) {
      return null;
    }
  }
}

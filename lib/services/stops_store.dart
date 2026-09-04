import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../models/bus_stop.dart';
import 'gtfs_stops.dart';
import 'olho_vivo_client.dart';
import 'parse_off_thread.dart';

typedef TextLoader = Future<String?> Function();

class StopsStore {
  StopsStore({
    required this._olhoVivo,
    Future<Directory> Function()? directory,
    TextLoader? gtfsLoader,
    this.maxAge = const Duration(days: 7),
  }) : _directory = directory ?? getApplicationSupportDirectory,
       _gtfsLoader = gtfsLoader ?? _loadBundledGtfs;

  static const gtfsAsset = 'assets/gtfs/stops.txt';
  static const _fileName = 'sptrans_stops.json';
  static const _distance = Distance();

  final OlhoVivoClient _olhoVivo;
  final Future<Directory> Function() _directory;
  final TextLoader _gtfsLoader;
  final Duration maxAge;

  List<BusStop>? _stops;
  Map<int, BusStop>? _byCode;
  bool _hasGtfs = false;
  Future<List<BusStop>>? _loading;

  bool get isLoaded => _stops != null;

  bool get hasFullCoverage => _hasGtfs;

  Future<Map<int, BusStop>> byCode() async {
    final stops = await load();
    return _byCode ??= {for (final stop in stops) stop.code: stop};
  }

  Future<List<BusStop>> load({bool refresh = false}) {
    final stops = _stops;
    if (!refresh && stops != null) return Future.value(stops);
    return _loading ??= _load(refresh).whenComplete(() => _loading = null);
  }

  Future<List<NearbyStop>> nearby(
    LatLng center,
    double radiusMeters, {
    LatLng? measureFrom,
    int limit = 400,
  }) async {
    final stops = await load();
    final from = measureFrom ?? center;
    final dLat = radiusMeters / 111320;
    final dLng = dLat / cos(center.latitude * pi / 180);

    final result = <NearbyStop>[];
    for (final stop in stops) {
      final p = stop.position;
      if ((p.latitude - center.latitude).abs() > dLat ||
          (p.longitude - center.longitude).abs() > dLng) {
        continue;
      }
      if (_distance(center, p) > radiusMeters) continue;
      result.add(NearbyStop(stop: stop, distanceMeters: _distance(from, p)));
    }
    result.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return result.length > limit ? result.sublist(0, limit) : result;
  }

  Future<List<BusStop>> _load(bool refresh) async {
    final gtfs = await _loadGtfs();
    _hasGtfs = gtfs.isNotEmpty;

    List<BusStop> api;
    try {
      api = await _loadFromApi(refresh);
    } catch (_) {
      if (gtfs.isEmpty) rethrow;
      api = const [];
    }

    final merged = {
      for (final stop in api) stop.code: stop,
      for (final stop in gtfs) stop.code: stop,
    };
    _byCode = merged;
    return _stops = merged.values.toList();
  }

  Future<List<BusStop>> _loadGtfs() async {
    try {
      final csv = await _gtfsLoader();
      if (csv == null || csv.isEmpty) return const [];
      return await parseOffThread(csv, parseGtfsStops);
    } catch (_) {
      return const [];
    }
  }

  Future<List<BusStop>> _loadFromApi(bool refresh) async {
    final file = File('${(await _directory()).path}${Platform.pathSeparator}$_fileName');
    final cached = refresh ? null : await _readCache(file);
    if (cached != null && cached.fresh) return cached.stops;

    try {
      final json = await _olhoVivo.allStopsJson();
      final stops = await parseOffThread(json, _parseJson);
      if (stops.isEmpty) {
        throw const OlhoVivoException('SPTrans returned an empty stop list.');
      }
      await file.writeAsString(json, flush: true);
      return stops;
    } catch (_) {
      if (cached != null) return cached.stops;
      rethrow;
    }
  }

  Future<({List<BusStop> stops, bool fresh})?> _readCache(File file) async {
    if (!await file.exists()) return null;
    try {
      final path = file.path;
      final stops = await Isolate.run(() => _parseJson(File(path).readAsStringSync()));
      if (stops.isEmpty) return null;
      final age = DateTime.now().difference(await file.lastModified());
      return (stops: stops, fresh: age < maxAge);
    } catch (_) {
      return null;
    }
  }

  static List<BusStop> _parseJson(String json) => OlhoVivoClient.parseStops(jsonDecode(json));

  static Future<String?> _loadBundledGtfs() async {
    try {
      return await rootBundle.loadString(gtfsAsset);
    } catch (_) {
      return null;
    }
  }
}

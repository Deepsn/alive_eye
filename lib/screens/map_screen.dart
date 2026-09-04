import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../models/bus_stop.dart';
import '../models/stop_forecast.dart';
import '../models/vehicle_position.dart';
import '../services/arrival_alerts.dart';
import '../services/line_route_service.dart';
import '../services/olho_vivo_client.dart';
import '../services/schedule_service.dart';
import '../services/stops_store.dart';
import '../services/token_store.dart';
import '../widgets/line_sheet.dart';
import '../widgets/stop_arrivals_sheet.dart';
import '../widgets/token_dialog.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.client,
    required this.stops,
    required this.routes,
    required this.tokenStore,
    required this.alerts,
    required this.schedules,
  });

  final OlhoVivoClient client;
  final StopsStore stops;
  final LineRouteService routes;
  final TokenStore tokenStore;
  final ArrivalAlerts alerts;
  final ScheduleService schedules;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _defaultZoom = 17.0;
  static const _minZoomForStops = 15.0;
  static const _distance = Distance();
  static const _debounce = Duration(milliseconds: 200);

  final _mapController = MapController();
  final _mapReady = Completer<void>();
  Timer? _debounceTimer;

  LatLng? _userPosition;
  String? _locationNote;

  List<NearbyStop> _stops = const [];
  bool _busy = false;
  String? _error;
  bool _needsToken = false;
  bool _zoomedOut = false;
  int _refreshId = 0;

  NearbyStop? _selected;
  StopForecast? _selectedForecast;

  LineForecast? _selectedLine;
  int? _selectedPrefix;
  LineSnapshot? _lineSnapshot;
  bool _lineFitted = false;

  @override
  void initState() {
    super.initState();
    widget.alerts.addListener(_onAlertsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    widget.alerts.removeListener(_onAlertsChanged);
    _debounceTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _onAlertsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    if (await widget.tokenStore.read() == null) await _editToken();
    await _goToUserLocation();
  }

  Future<void> _editToken() async {
    final current = await widget.tokenStore.read();
    if (!mounted) return;
    final token = await showTokenDialog(context, current: current);
    if (token == null) return;
    await widget.tokenStore.write(token);
    widget.client.resetSession();
    await _refreshStops();
  }

  Future<void> _goToUserLocation() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final position = await _locate();
    if (!mounted) return;
    await _mapReady.future;
    _userPosition = position;
    _mapController.move(position ?? AppConfig.fallbackCenter, _defaultZoom);
    await _refreshStops();
  }

  Future<LatLng?> _locate() async {
    const fallback = 'showing central São Paulo instead.';
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _locationNote = 'Location services are off, $fallback';
        return null;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _locationNote = 'Location permission denied, $fallback';
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      _locationNote = null;
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      _locationNote = 'Could not get your location ($e), $fallback';
      return null;
    }
  }

  Future<void> _refreshStops({bool redownload = false}) async {
    final id = ++_refreshId;
    final camera = _mapController.camera;
    final zoomedOut = camera.zoom < _minZoomForStops;
    setState(() {
      _busy = true;
      _error = null;
      _needsToken = false;
      _zoomedOut = zoomedOut;
    });

    try {
      if (redownload) await widget.stops.load(refresh: true);
      final stops = zoomedOut
          ? const <NearbyStop>[]
          : await widget.stops.nearby(
              camera.center,
              _distance(camera.center, camera.visibleBounds.northEast),
              measureFrom: _userPosition,
            );
      if (!mounted || id != _refreshId) return;
      setState(() {
        _stops = stops;
        _busy = false;
      });
    } on OlhoVivoAuthException catch (e) {
      if (!mounted || id != _refreshId) return;
      setState(() {
        _error = e.message;
        _needsToken = true;
        _busy = false;
      });
    } catch (e) {
      if (!mounted || id != _refreshId) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _refreshStops);
  }

  void _select(NearbyStop? stop) {
    setState(() {
      _selected = stop;
      _selectedForecast = null;
      _clearLine();
    });
  }

  void _clearLine() {
    _selectedLine = null;
    _selectedPrefix = null;
    _lineSnapshot = null;
    _lineFitted = false;
  }

  void _selectLine(LineForecast line, int prefix) {
    setState(() {
      if (_selectedLine?.lineCode != line.lineCode) {
        _lineSnapshot = null;
        _lineFitted = false;
      }
      _selectedLine = line;
      _selectedPrefix = prefix;
    });
  }

  void _focusVehicle(VehiclePosition vehicle) {
    setState(() => _selectedPrefix = vehicle.prefix);
    final zoom = _mapController.camera.zoom;
    _mapController.move(vehicle.position, zoom < 15 ? 15 : zoom);
  }

  void _onLineSnapshot(LineSnapshot? snapshot) {
    setState(() => _lineSnapshot = snapshot);
    if (snapshot == null || _lineFitted) return;
    final points = [
      ...snapshot.path,
      for (final v in snapshot.vehicles) v.position,
    ];
    if (points.length < 2) return;
    _lineFitted = true;
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: EdgeInsets.fromLTRB(
          40,
          120,
          40,
          MediaQuery.sizeOf(context).height * 0.5,
        ),
        maxZoom: 16,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selected;
    final line = _selectedLine;
    final snapshot = _lineSnapshot;
    final visible = line != null
        ? [?selected]
        : [
            ..._stops,
            if (selected != null && !_stops.any((s) => s.stop == selected.stop))
              selected,
          ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alive Eye'),
        actions: [
          IconButton(
            tooltip: 'SPTrans API token',
            onPressed: _editToken,
            icon: const Icon(Icons.key),
          ),
          PopupMenuButton<void>(
            itemBuilder: (_) => [
              PopupMenuItem(
                onTap: () => _refreshStops(redownload: true),
                child: const Text('Re-download stop list'),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: AppConfig.fallbackCenter,
              initialZoom: _defaultZoom,
              onMapReady: _mapReady.complete,
              onPositionChanged: _onPositionChanged,
              onTap: (_, _) => _select(null),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: AppConfig.packageName,
              ),
              if (snapshot != null && snapshot.path.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: snapshot.path,
                      strokeWidth: 5,
                      color: scheme.primary.withValues(alpha: 0.8),
                      borderStrokeWidth: 2,
                      borderColor: scheme.surface,
                    ),
                  ],
                ),
              if (snapshot != null)
                CircleLayer(
                  circles: [
                    for (final stop in snapshot.stops)
                      CircleMarker(
                        point: stop.position,
                        radius: 4,
                        color: scheme.surface,
                        borderColor: scheme.primary,
                        borderStrokeWidth: 2,
                      ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_userPosition case final position?)
                    Marker(
                      point: position,
                      width: 22,
                      height: 22,
                      child: const _UserMarker(),
                    ),
                  for (final nearby in visible)
                    Marker(
                      point: nearby.stop.position,
                      width: 40,
                      height: 40,
                      child: _StopMarker(
                        selected: nearby.stop == selected?.stop,
                        alerted: widget.alerts.watchesStop(nearby.stop.code),
                        onTap: () => _select(nearby),
                      ),
                    ),
                  if (line == null)
                    for (final lineForecast
                        in _selectedForecast?.lines ?? const <LineForecast>[])
                      for (final vehicle in lineForecast.vehicles)
                        Marker(
                          point: vehicle.position,
                          width: 72,
                          height: 30,
                          child: _BusMarker(
                            label: vehicle.etaLabel,
                            selected: false,
                            onTap: () =>
                                _selectLine(lineForecast, vehicle.prefix),
                          ),
                        ),
                  if (snapshot != null)
                    for (final vehicle in snapshot.vehicles)
                      Marker(
                        point: vehicle.position,
                        width: 72,
                        height: 30,
                        child: _BusMarker(
                          label:
                              snapshot.etaByPrefix[vehicle.prefix]?.etaLabel ??
                              '${vehicle.prefix}',
                          selected: vehicle.prefix == _selectedPrefix,
                          onTap: () => _focusVehicle(vehicle),
                        ),
                      ),
                ],
              ),
              const RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: _StatusBanner(
              busy: _busy,
              downloading: _busy && !widget.stops.isLoaded,
              error: _error,
              needsToken: _needsToken,
              zoomedOut: _zoomedOut,
              stopCount: _stops.length,
              locationNote: _locationNote,
              coverageNote:
                  widget.stops.isLoaded && !widget.stops.hasFullCoverage
                  ? 'The API only lists corridor stops. Add ${StopsStore.gtfsAsset} '
                        'for every stop in the city.'
                  : null,
              onRetry: _refreshStops,
              onEditToken: _editToken,
            ),
          ),
          if (selected == null)
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                tooltip: 'My location',
                onPressed: _busy ? null : _goToUserLocation,
                child: const Icon(Icons.my_location),
              ),
            )
          else
            Positioned.fill(
              child: DraggableScrollableSheet(
                initialChildSize: 0.45,
                minChildSize: 0.15,
                maxChildSize: 0.92,
                snap: true,
                snapSizes: const [0.15, 0.45, 0.92],
                builder: (context, scrollController) => line == null
                    ? StopArrivalsSheet(
                        stop: selected,
                        client: widget.client,
                        alerts: widget.alerts,
                        schedules: widget.schedules,
                        scrollController: scrollController,
                        onClose: () => _select(null),
                        onForecastChanged: (forecast) =>
                            setState(() => _selectedForecast = forecast),
                        onVehicleTap: (line, vehicle) =>
                            _selectLine(line, vehicle.prefix),
                      )
                    : LineSheet(
                        stop: selected,
                        line: line,
                        selectedPrefix: _selectedPrefix,
                        client: widget.client,
                        routes: widget.routes,
                        alerts: widget.alerts,
                        scrollController: scrollController,
                        onBack: () => setState(_clearLine),
                        onClose: () => _select(null),
                        onSnapshot: _onLineSnapshot,
                        onVehicleTap: _focusVehicle,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.busy,
    required this.downloading,
    required this.error,
    required this.needsToken,
    required this.zoomedOut,
    required this.stopCount,
    required this.locationNote,
    required this.coverageNote,
    required this.onRetry,
    required this.onEditToken,
  });

  final bool busy;
  final bool downloading;
  final String? error;
  final bool needsToken;
  final bool zoomedOut;
  final int stopCount;
  final String? locationNote;
  final String? coverageNote;
  final VoidCallback onRetry;
  final VoidCallback onEditToken;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = downloading
        ? 'Downloading the SPTrans stop list (first run only)…'
        : busy
        ? 'Updating…'
        : error ??
              (zoomedOut
                  ? 'Zoom in to see stops.'
                  : '$stopCount stop${stopCount == 1 ? '' : 's'} in view');

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: .start,
          mainAxisSize: .min,
          children: [
            Row(
              children: [
                if (busy) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: error != null ? theme.colorScheme.error : null,
                    ),
                  ),
                ),
                if (!busy && needsToken)
                  TextButton(
                    onPressed: onEditToken,
                    child: const Text('Set token'),
                  )
                else if (!busy && error != null)
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
              ],
            ),
            for (final note in [locationNote, coverageNote].nonNulls)
              Text(note, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _StopMarker extends StatelessWidget {
  const _StopMarker({
    required this.selected,
    required this.alerted,
    required this.onTap,
  });

  final bool selected;
  final bool alerted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Center(
        child: Stack(
          alignment: .center,
          clipBehavior: .none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: selected ? 36 : 28,
              height: selected ? 36 : 28,
              decoration: BoxDecoration(
                color: selected ? scheme.primary : scheme.primaryContainer,
                shape: .circle,
                border: Border.all(color: scheme.surface, width: 2),
                boxShadow: const [
                  BoxShadow(blurRadius: 4, color: Colors.black26),
                ],
              ),
              child: Icon(
                Icons.directions_bus,
                size: selected ? 20 : 16,
                color: selected ? scheme.onPrimary : scheme.onPrimaryContainer,
              ),
            ),
            if (alerted)
              Positioned(
                right: 0,
                top: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    shape: .circle,
                    border: Border.all(color: scheme.primary, width: 1.5),
                  ),
                  child: Icon(
                    Icons.notifications_active,
                    size: 10,
                    color: scheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BusMarker extends StatelessWidget {
  const _BusMarker({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected ? scheme.primary : scheme.tertiaryContainer;
    final foreground = selected ? scheme.onPrimary : scheme.onTertiaryContainer;

    return GestureDetector(
      onTap: onTap,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: scheme.surface,
              width: selected ? 2.5 : 1.5,
            ),
            boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black26)],
          ),
          child: Row(
            mainAxisSize: .min,
            children: [
              Icon(Icons.directions_bus, size: 14, color: foreground),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: .bold,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserMarker extends StatelessWidget {
  const _UserMarker();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.blue,
        shape: .circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
      ),
    );
  }
}

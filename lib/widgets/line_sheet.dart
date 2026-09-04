import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/bus_stop.dart';
import '../models/line_stops_forecast.dart';
import '../models/stop_forecast.dart';
import '../models/vehicle_position.dart';
import '../services/arrival_alerts.dart';
import '../services/line_route_service.dart';
import '../services/olho_vivo_client.dart';
import '../services/route_path.dart';
import 'alert_button.dart';
import 'line_badge.dart';

class LineSnapshot {
  const LineSnapshot({
    required this.path,
    required this.stops,
    required this.vehicles,
    required this.etaByPrefix,
    required this.fromSchedule,
  });

  final List<LatLng> path;
  final List<BusStop> stops;
  final List<VehiclePosition> vehicles;
  final Map<int, VehicleForecast> etaByPrefix;
  final bool fromSchedule;
}

class LineSheet extends StatefulWidget {
  const LineSheet({
    super.key,
    required this.stop,
    required this.line,
    required this.selectedPrefix,
    required this.client,
    required this.routes,
    required this.alerts,
    required this.scrollController,
    required this.onBack,
    required this.onClose,
    required this.onSnapshot,
    required this.onVehicleTap,
  });

  static const refreshInterval = Duration(seconds: 15);

  final NearbyStop stop;
  final LineForecast line;
  final int? selectedPrefix;
  final OlhoVivoClient client;
  final LineRouteService routes;
  final ArrivalAlerts alerts;
  final ScrollController scrollController;
  final VoidCallback onBack;
  final VoidCallback onClose;
  final ValueChanged<LineSnapshot?> onSnapshot;
  final ValueChanged<VehiclePosition> onVehicleTap;

  @override
  State<LineSheet> createState() => _LineSheetState();
}

class _LineSheetState extends State<LineSheet> {
  static const _distance = Distance();

  LinePositions? _positions;
  LineForecast? _atStop;
  LineStopsForecast? _lineStops;
  LineRoute? _route;
  bool _routeResolved = false;
  Object? _error;
  bool _loading = true;
  bool _refreshing = false;
  Timer? _timer;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(LineSheet.refreshInterval, (_) => _load(silent: true));
  }

  @override
  void didUpdateWidget(LineSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.lineCode != widget.line.lineCode ||
        oldWidget.stop.stop.code != widget.stop.stop.code) {
      _positions = null;
      _atStop = null;
      _lineStops = null;
      _route = null;
      _routeResolved = false;
      _error = null;
      _load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final id = ++_requestId;
    setState(() {
      _refreshing = true;
      if (!silent) {
        _loading = true;
        _error = null;
      }
    });
    try {
      final positions = await widget.client.linePositions(widget.line.lineCode);
      final atStop = await _arrivalsAtStop();
      await _resolveRoute();
      if (!mounted || id != _requestId) return;
      setState(() {
        _positions = positions;
        _atStop = atStop;
        _error = null;
        _loading = false;
        _refreshing = false;
      });
      widget.onSnapshot(_snapshot());
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _error = e;
        _loading = false;
        _refreshing = false;
      });
    }
  }

  // Previsao/Linha only covers corridor stops, so arrival times for the
  // selected stop come from Previsao/Parada, which works for every stop.
  Future<LineForecast?> _arrivalsAtStop() async {
    try {
      final forecast = await widget.client.stopForecast(widget.stop.stop.code);
      for (final line in forecast?.lines ?? const <LineForecast>[]) {
        if (line.lineCode == widget.line.lineCode) return line;
      }
      return null;
    } catch (_) {
      return _atStop;
    }
  }

  Future<void> _resolveRoute() async {
    if (_routeResolved) return;
    _lineStops ??= await _lineStopsOrNull();
    _route = await widget.routes.resolve(
      signage: widget.line.signage,
      direction: widget.line.direction,
      hintStopIds: {for (final s in _lineStops?.stops ?? const []) s.stop.code},
    );
    _routeResolved = _route != null || _lineStops != null;
  }

  Future<LineStopsForecast?> _lineStopsOrNull() async {
    try {
      return await widget.client.lineStopsForecast(widget.line.lineCode);
    } catch (_) {
      return null;
    }
  }

  LineSnapshot? _snapshot() {
    final positions = _positions;
    if (positions == null) return null;
    final route = _route;
    final stops = route?.stops ??
        [for (final s in orderLineStops(_lineStops?.stops ?? const [])) s.stop];
    return LineSnapshot(
      path: route?.path ?? [for (final s in stops) s.position],
      stops: stops,
      vehicles: positions.vehicles,
      etaByPrefix: {for (final v in _atStop?.vehicles ?? const []) v.prefix: v},
      fromSchedule: route != null,
    );
  }

  List<VehiclePosition> _sortedVehicles(Map<int, VehicleForecast> etas) {
    final stopPosition = widget.stop.stop.position;
    return [...?_positions?.vehicles]..sort((a, b) {
      final ea = etas[a.prefix]?.etaMinutes;
      final eb = etas[b.prefix]?.etaMinutes;
      if (ea != null && eb != null) return ea.compareTo(eb);
      if (ea != null) return -1;
      if (eb != null) return 1;
      return _distance(stopPosition, a.position).compareTo(_distance(stopPosition, b.position));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = widget.line;
    final etas = {for (final v in _atStop?.vehicles ?? const <VehicleForecast>[]) v.prefix: v};
    final vehicles = _sortedVehicles(etas);

    return Material(
      color: theme.colorScheme.surface,
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: .antiAlias,
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: .start,
            children: [
              IconButton(
                tooltip: 'Back to stop',
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
              ),
              LineBadge(signage: line.signage),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text('→ ${line.destination}', style: theme.textTheme.titleMedium),
                    if (line.origin.isNotEmpty)
                      Text('from ${line.origin}', style: theme.textTheme.bodySmall),
                    Text(
                      'Arrivals at ${widget.stop.stop.displayName}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              AlertButton(
                alerts: widget.alerts,
                stop: widget.stop.stop,
                lineCode: widget.line.lineCode,
                signage: widget.line.signage,
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _statusLine(theme),
          const SizedBox(height: 8),
          if (_positions == null && _loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_positions == null && _error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
                  const SizedBox(height: 8),
                  Text('$_error', textAlign: .center, style: TextStyle(color: theme.colorScheme.error)),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          else if (vehicles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(Icons.no_transfer, size: 40),
                  SizedBox(height: 8),
                  Text('No buses running on this line right now.', textAlign: .center),
                ],
              ),
            )
          else
            for (final vehicle in vehicles)
              _VehicleTile(
                vehicle: vehicle,
                eta: etas[vehicle.prefix],
                predicted: _atStop != null,
                distanceToStop: _distance(widget.stop.stop.position, vehicle.position),
                selected: vehicle.prefix == widget.selectedPrefix,
                onTap: () => widget.onVehicleTap(vehicle),
              ),
        ],
      ),
    );
  }

  Widget _statusLine(ThemeData theme) {
    if (_loading) return const LinearProgressIndicator(minHeight: 2);
    final positions = _positions;
    if (positions == null) return const SizedBox.shrink();
    final count = positions.vehicles.length;
    final route = _route;
    final stopCount = route?.stops.length ?? _lineStops?.stops.length ?? 0;
    return Row(
      children: [
        if (_refreshing) ...[
          const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            '$count bus${count == 1 ? '' : 'es'} on this line · $stopCount stops'
            '${route == null ? ' (corridor stops only)' : ''} · '
            '${_refreshing ? 'refreshing…' : 'updated at ${positions.referenceTime}, '
                'every ${LineSheet.refreshInterval.inSeconds} s'}',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _VehicleTile extends StatelessWidget {
  const _VehicleTile({
    required this.vehicle,
    required this.eta,
    required this.predicted,
    required this.distanceToStop,
    required this.selected,
    required this.onTap,
  });

  final VehiclePosition vehicle;
  final VehicleForecast? eta;
  final bool predicted;
  final double distanceToStop;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final distanceLabel = distanceToStop < 1000
        ? '${distanceToStop.round()} m from stop'
        : '${(distanceToStop / 1000).toStringAsFixed(1)} km from stop';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: selected ? theme.colorScheme.primaryContainer : null,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          Icons.directions_bus,
          color: selected ? theme.colorScheme.primary : theme.colorScheme.secondary,
        ),
        title: Row(
          children: [
            Text('Bus ${vehicle.prefix}'),
            if (vehicle.accessible) ...[
              const SizedBox(width: 6),
              Icon(Icons.accessible, size: 16, color: theme.colorScheme.tertiary),
            ],
          ],
        ),
        subtitle: Text(distanceLabel),
        trailing: eta == null
            ? Text(
                predicted ? 'passed' : 'no prediction',
                style: theme.textTheme.bodySmall,
              )
            : Column(
                mainAxisAlignment: .center,
                crossAxisAlignment: .end,
                children: [
                  Text(
                    eta!.etaLabel,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: .bold),
                  ),
                  Text(eta!.arrivalTime, style: theme.textTheme.bodySmall),
                ],
              ),
      ),
    );
  }
}

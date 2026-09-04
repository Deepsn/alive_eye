import 'dart:async';

import 'package:flutter/material.dart';

import '../models/bus_stop.dart';
import '../models/stop_forecast.dart';
import '../services/arrival_alerts.dart';
import '../services/olho_vivo_client.dart';
import '../services/schedule_service.dart';
import 'alert_button.dart';
import 'line_badge.dart';

typedef VehicleTapCallback = void Function(LineForecast line, VehicleForecast vehicle);

class StopArrivalsSheet extends StatefulWidget {
  const StopArrivalsSheet({
    super.key,
    required this.stop,
    required this.client,
    required this.alerts,
    required this.schedules,
    required this.scrollController,
    required this.onClose,
    required this.onForecastChanged,
    required this.onVehicleTap,
  });

  static const refreshInterval = Duration(seconds: 30);

  final NearbyStop stop;
  final OlhoVivoClient client;
  final ArrivalAlerts alerts;
  final ScheduleService schedules;
  final ScrollController scrollController;
  final VoidCallback onClose;
  final ValueChanged<StopForecast?> onForecastChanged;
  final VehicleTapCallback onVehicleTap;

  @override
  State<StopArrivalsSheet> createState() => _StopArrivalsSheetState();
}

class _StopArrivalsSheetState extends State<StopArrivalsSheet> {
  StopForecast? _forecast;
  List<StopSchedule> _schedules = const [];
  Object? _error;
  bool _loading = true;
  bool _refreshing = false;
  Timer? _timer;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(StopArrivalsSheet.refreshInterval, (_) => _load(silent: true));
  }

  @override
  void didUpdateWidget(StopArrivalsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stop.stop.code != widget.stop.stop.code) {
      _forecast = null;
      _schedules = const [];
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
    final schedules = await _schedulesOrEmpty();
    if (!mounted || id != _requestId) return;

    try {
      final forecast = await widget.client.stopForecast(widget.stop.stop.code);
      if (!mounted || id != _requestId) return;
      setState(() {
        _schedules = schedules;
        _forecast = forecast;
        _error = null;
        _loading = false;
        _refreshing = false;
      });
      widget.onForecastChanged(forecast);
      if (forecast != null) await widget.alerts.consider(forecast);
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _schedules = schedules;
        _error = e;
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<List<StopSchedule>> _schedulesOrEmpty() async {
    try {
      return await widget.schedules.at(widget.stop.stop.code);
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stop = widget.stop.stop;

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
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(stop.displayName, style: theme.textTheme.titleLarge),
                    if (stop.name.isNotEmpty && stop.address.isNotEmpty)
                      Text(stop.address, style: theme.textTheme.bodyMedium),
                    Text(
                      'Stop ${stop.code} · ${widget.stop.distanceLabel} away',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              AlertButton(alerts: widget.alerts, stop: stop),
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
          ..._body(theme),
        ],
      ),
    );
  }

  Widget _statusLine(ThemeData theme) {
    if (_loading) return const LinearProgressIndicator(minHeight: 2);

    final forecast = _forecast;
    final text = _error != null && forecast != null
        ? 'Could not refresh: $_error'
        : _refreshing
        ? 'Refreshing…'
        : forecast != null
        ? 'Updated at ${forecast.referenceTime}, every '
              '${StopArrivalsSheet.refreshInterval.inSeconds} s'
        : '';
    return Row(
      children: [
        if (_refreshing && _error == null) ...[
          const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: _error != null ? theme.colorScheme.error : null,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _body(ThemeData theme) {
    final forecast = _forecast;

    if (forecast == null && _loading) {
      return const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (forecast == null && _error != null && _schedules.isEmpty) {
      return [
        _Message(
          icon: Icons.error_outline,
          text: '$_error',
          color: theme.colorScheme.error,
          action: TextButton(onPressed: _load, child: const Text('Retry')),
        ),
      ];
    }

    final live = forecast?.lines ?? const <LineForecast>[];
    final tracked = {for (final line in live) line.signage};
    final timetabled = [
      for (final schedule in _schedules)
        if (!tracked.contains(schedule.signage)) schedule,
    ];

    if (live.isEmpty && timetabled.isEmpty) {
      return const [
        _Message(
          icon: Icons.no_transfer,
          text: 'No buses heading to this stop right now.',
        ),
      ];
    }

    return [
      for (final line in live)
        _LineCard(
          line: line,
          alerts: widget.alerts,
          stop: widget.stop.stop,
          onVehicleTap: (v) => widget.onVehicleTap(line, v),
        ),
      if (timetabled.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
          child: Text(
            live.isEmpty
                ? 'No bus is being tracked right now. These lines serve this '
                      'stop on the timetable:'
                : 'Also on the timetable here, with no bus reporting in:',
            style: theme.textTheme.bodySmall,
          ),
        ),
        for (final schedule in timetabled)
          _ScheduledCard(
            schedule: schedule,
            alerts: widget.alerts,
            stop: widget.stop.stop,
          ),
      ],
    ];
  }
}

class _ScheduledCard extends StatelessWidget {
  const _ScheduledCard({
    required this.schedule,
    required this.alerts,
    required this.stop,
  });

  final StopSchedule schedule;
  final ArrivalAlerts alerts;
  final BusStop stop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Opacity(
              opacity: schedule.running ? 1 : 0.5,
              child: LineBadge(signage: schedule.signage),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  if (schedule.headsign.isNotEmpty)
                    Text('→ ${schedule.headsign}', style: theme.textTheme.titleSmall),
                  Row(
                    children: [
                      Icon(
                        schedule.running ? Icons.schedule : Icons.bedtime_outlined,
                        size: 14,
                        color: muted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          schedule.label,
                          style: theme.textTheme.bodySmall?.copyWith(color: muted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            AlertButton.scheduled(
              alerts: alerts,
              stop: stop,
              signage: schedule.signage,
              dense: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.alerts,
    required this.stop,
    required this.onVehicleTap,
  });

  final LineForecast line;
  final ArrivalAlerts alerts;
  final BusStop stop;
  final ValueChanged<VehicleForecast> onVehicleTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Row(
              children: [
                LineBadge(signage: line.signage),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      Text('→ ${line.destination}', style: theme.textTheme.titleSmall),
                      if (line.origin.isNotEmpty)
                        Text('from ${line.origin}', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                AlertButton(
                  alerts: alerts,
                  stop: stop,
                  lineCode: line.lineCode,
                  signage: line.signage,
                  dense: true,
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final vehicle in line.vehicles)
              _VehicleRow(vehicle: vehicle, onTap: () => onVehicleTap(vehicle)),
          ],
        ),
      ),
    );
  }
}

class _VehicleRow extends StatelessWidget {
  const _VehicleRow({required this.vehicle, required this.onTap});

  final VehicleForecast vehicle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(Icons.directions_bus, size: 18, color: theme.colorScheme.secondary),
            const SizedBox(width: 8),
            Text('Bus ${vehicle.prefix}'),
            if (vehicle.accessible) ...[
              const SizedBox(width: 6),
              Icon(Icons.accessible, size: 16, color: theme.colorScheme.tertiary),
            ],
            const Spacer(),
            Text(
              vehicle.etaLabel,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: .bold,
                color: vehicle.etaMinutes <= 2 ? theme.colorScheme.primary : null,
              ),
            ),
            const SizedBox(width: 8),
            Text(vehicle.arrivalTime, style: theme.textTheme.bodySmall),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.color,
    this.action,
  });

  final IconData icon;
  final String text;
  final Color? color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: 8),
          Text(text, textAlign: .center, style: TextStyle(color: color)),
          ?action,
        ],
      ),
    );
  }
}

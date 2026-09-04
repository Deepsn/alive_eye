import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/bus_stop.dart';
import '../models/stop_forecast.dart';
import 'alert_store.dart';
import 'notifications.dart';
import 'olho_vivo_client.dart';

class ArrivalAlerts extends ChangeNotifier {
  ArrivalAlerts({
    required this._client,
    required this._notifier,
    AlertStore? store,
    this.pollInterval = const Duration(seconds: 30),
    this.nearMinutes = 3,
  }) : _store = store ?? AlertStore();

  final OlhoVivoClient _client;
  final Notifier _notifier;
  final AlertStore _store;
  final Duration pollInterval;
  final int nearMinutes;

  final _armed = <(int, int, String), AlertTarget>{};
  final _announced = <int, Set<int>>{};
  Timer? _timer;

  Iterable<AlertTarget> get targets => _armed.values;

  Iterable<int> get armedStops => {for (final key in _armed.keys) key.$1};

  bool watchesStop(int stopCode) => _armed.keys.any((key) => key.$1 == stopCode);

  bool watchesEveryLine(int stopCode) =>
      _armed.values.any((target) => target.stopCode == stopCode && target.isEveryLine);

  bool watchesLine(int stopCode, {required int lineCode, required String signage}) =>
      _armed.values.any(
        (target) =>
            target.stopCode == stopCode &&
            target.covers(lineCode: lineCode, signage: signage),
      );

  Future<void> restore() async {
    final saved = await _store.read();
    if (saved.isEmpty) return;
    _armed.addEntries([for (final target in saved) MapEntry(target.key, target)]);
    _rearmTimer();
    notifyListeners();
  }

  Future<bool> toggleEveryLine(BusStop stop) => _toggle(
    AlertTarget.everyLine(stopCode: stop.code, stopName: stop.displayName),
  );

  Future<bool> toggleLine(
    BusStop stop, {
    required int lineCode,
    required String signage,
  }) => _toggle(
    AlertTarget(
      stopCode: stop.code,
      stopName: stop.displayName,
      lineCode: lineCode,
      lineSignage: signage,
    ),
  );

  Future<void> poll() async {
    for (final stopCode in armedStops.toList()) {
      try {
        final forecast = await _client.stopForecast(stopCode);
        if (forecast != null) await consider(forecast);
      } catch (_) {}
    }
  }

  Future<void> consider(StopForecast forecast) async {
    final watching = [
      for (final target in _armed.values)
        if (target.stopCode == forecast.stopCode) target,
    ];
    if (watching.isEmpty) return;

    final announced = _announced.putIfAbsent(forecast.stopCode, () => <int>{});
    final present = <int>{};
    for (final line in forecast.lines) {
      final target = _match(watching, line);
      for (final vehicle in line.vehicles) {
        present.add(vehicle.prefix);
        if (target == null || vehicle.etaMinutes > nearMinutes) continue;
        if (!announced.add(vehicle.prefix)) continue;
        await _notifier.show(
          id: Object.hash(forecast.stopCode, vehicle.prefix) & 0x7fffffff,
          title: vehicle.etaMinutes == 0
              ? '${line.signage} is arriving'
              : '${line.signage} in ${vehicle.etaLabel}',
          body: '${target.stopName} → ${line.destination}',
        );
      }
    }
    announced.retainWhere(present.contains);
  }

  static AlertTarget? _match(List<AlertTarget> watching, LineForecast line) {
    for (final target in watching) {
      if (target.covers(lineCode: line.lineCode, signage: line.signage)) return target;
    }
    return null;
  }

  // A line can be watched by `cl` code and by signage at the same stop, so a
  // toggle clears every target that overlaps the one being tapped.
  Future<bool> _toggle(AlertTarget target) async {
    final overlapping = <(int, int, String)>[];
    for (final armed in _armed.values) {
      if (armed.stopCode != target.stopCode) continue;
      if (target.isEveryLine || armed.isEveryLine) {
        if (target.isEveryLine && armed.isEveryLine) overlapping.add(armed.key);
        continue;
      }
      if (armed.covers(lineCode: target.lineCode, signage: target.lineSignage) ||
          target.covers(lineCode: armed.lineCode, signage: armed.lineSignage)) {
        overlapping.add(armed.key);
      }
    }

    if (overlapping.isNotEmpty) {
      for (final key in overlapping) {
        _armed.remove(key);
      }
      if (!watchesStop(target.stopCode)) _announced.remove(target.stopCode);
    } else {
      if (!await _notifier.enable()) return false;
      if (target.isEveryLine) {
        _armed.removeWhere((key, _) => key.$1 == target.stopCode);
      }
      _armed[target.key] = target;
    }

    _rearmTimer();
    notifyListeners();
    await _store.write(_armed.values);
    return _armed.containsKey(target.key);
  }

  void _rearmTimer() {
    if (_armed.isEmpty) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(pollInterval, (_) => poll());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

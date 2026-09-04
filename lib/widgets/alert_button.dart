import 'package:flutter/material.dart';

import '../models/bus_stop.dart';
import '../services/alert_store.dart';
import '../services/arrival_alerts.dart';

class AlertButton extends StatelessWidget {
  const AlertButton({
    super.key,
    required this.alerts,
    required this.stop,
    this.lineCode,
    this.signage = '',
    this.dense = false,
  });

  const AlertButton.scheduled({
    Key? key,
    required ArrivalAlerts alerts,
    required BusStop stop,
    required String signage,
    bool dense = false,
  }) : this(
         key: key,
         alerts: alerts,
         stop: stop,
         lineCode: AlertTarget.bySignage,
         signage: signage,
         dense: dense,
       );

  final ArrivalAlerts alerts;
  final BusStop stop;
  final int? lineCode;
  final String signage;
  final bool dense;

  bool get _wholeStop => lineCode == null;

  bool get _armed => _wholeStop
      ? alerts.watchesEveryLine(stop.code)
      : alerts.watchesLine(stop.code, lineCode: lineCode!, signage: signage);

  String get _tooltip {
    if (_wholeStop) {
      return _armed ? 'Stop watching every line here' : 'Notify me about any line here';
    }
    return _armed ? 'Stop watching $signage' : 'Notify me when $signage is near';
  }

  Future<void> _toggle(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);

    if (!_wholeStop && alerts.watchesEveryLine(stop.code)) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Every line at this stop is already watched.')),
      );
      return;
    }

    final wanted = !_armed;
    final armed = _wholeStop
        ? await alerts.toggleEveryLine(stop)
        : await alerts.toggleLine(stop, lineCode: lineCode!, signage: signage);

    messenger?.showSnackBar(
      SnackBar(content: Text(_message(wanted: wanted, armed: armed))),
    );
  }

  String _message({required bool wanted, required bool armed}) {
    if (wanted && !armed) {
      return 'Notifications are blocked for Alive Eye, turn them on in the '
          'system settings.';
    }
    final what = _wholeStop ? 'a bus' : signage;
    if (armed) {
      return 'You will be notified when $what is ${alerts.nearMinutes} min or '
          'less from ${stop.displayName}.';
    }
    return _wholeStop
        ? 'Arrival alerts off for ${stop.displayName}.'
        : 'Arrival alerts off for $signage at ${stop.displayName}.';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: alerts,
      builder: (context, _) => IconButton(
        tooltip: _tooltip,
        isSelected: _armed,
        visualDensity: dense ? VisualDensity.compact : null,
        onPressed: () => _toggle(context),
        icon: const Icon(Icons.notifications_none),
        selectedIcon: Icon(
          Icons.notifications_active,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

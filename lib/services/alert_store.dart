import 'package:shared_preferences/shared_preferences.dart';

class AlertTarget {
  const AlertTarget({
    required this.stopCode,
    required this.stopName,
    required this.lineCode,
    required this.lineSignage,
  });

  const AlertTarget.everyLine({required this.stopCode, required this.stopName})
    : lineCode = anyLine,
      lineSignage = '';

  static const anyLine = 0;

  // Lines that only exist in the GTFS timetable have no Olho Vivo `cl` code,
  // so they are matched by signage until they show up in a live forecast.
  static const bySignage = -1;

  final int stopCode;
  final String stopName;
  final int lineCode;
  final String lineSignage;

  bool get isEveryLine => lineCode == anyLine && lineSignage.isEmpty;

  (int, int, String) get key => (stopCode, lineCode, lineSignage);

  bool covers({required int lineCode, required String signage}) {
    if (isEveryLine) return true;
    if (this.lineCode == bySignage || lineCode == bySignage) {
      return lineSignage == signage;
    }
    return this.lineCode == lineCode;
  }
}

class AlertStore {
  AlertStore({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  static const _key = 'arrival_alert_stops';
  static const _separator = '\t';

  final SharedPreferencesAsync _prefs;

  Future<List<AlertTarget>> read() async {
    final rows = await _prefs.getStringList(_key) ?? const <String>[];
    final targets = <AlertTarget>[];
    for (final row in rows) {
      final parts = row.split(_separator);
      if (parts.length < 4) continue;
      final stopCode = int.tryParse(parts[0]);
      final lineCode = int.tryParse(parts[1]);
      if (stopCode == null || lineCode == null) continue;
      targets.add(AlertTarget(
        stopCode: stopCode,
        lineCode: lineCode,
        lineSignage: parts[2],
        stopName: parts.sublist(3).join(_separator),
      ));
    }
    return targets;
  }

  Future<void> write(Iterable<AlertTarget> targets) => _prefs.setStringList(_key, [
    for (final target in targets)
      [target.stopCode, target.lineCode, target.lineSignage, target.stopName]
          .join(_separator),
  ]);
}

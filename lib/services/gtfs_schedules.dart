import 'dart:convert';

class ServiceWindow {
  const ServiceWindow({
    required this.startMinute,
    required this.endMinute,
    required this.headwaySeconds,
  });

  final int startMinute;
  final int endMinute;
  final int headwaySeconds;

  int get headwayMinutes => (headwaySeconds / 60).round().clamp(1, 1 << 30);

  bool contains(int minuteOfDay) =>
      minuteOfDay >= startMinute && minuteOfDay <= endMinute;
}

class ScheduledLine {
  const ScheduledLine({
    required this.signage,
    required this.directionId,
    required this.headsign,
    required this.serviceDays,
    required this.offsetMinutes,
    required this.windows,
  });

  final String signage;
  final int directionId;
  final String headsign;
  final String serviceDays;
  final int offsetMinutes;
  final List<ServiceWindow> windows;

  bool runsOn(DateTime day) =>
      serviceDays.length == 7 && serviceDays[day.weekday - 1] == '1';

  // The bus reaching this stop at [now] left the first stop offsetMinutes ago,
  // so the frequency window is looked up against that departure.
  ServiceWindow? windowAt(DateTime now) {
    if (!runsOn(now)) return null;
    final departure = now.hour * 60 + now.minute - offsetMinutes;
    for (final window in windows) {
      if (window.contains(departure) || window.contains(departure + 1440)) {
        return window;
      }
    }
    return null;
  }

  ServiceWindow? get firstWindow => windows.isEmpty ? null : windows.first;

  ServiceWindow? get lastWindow => windows.isEmpty ? null : windows.last;
}

class GtfsSchedules {
  const GtfsSchedules(this._byStop);

  static const empty = GtfsSchedules(<int, List<ScheduledLine>>{});

  final Map<int, List<ScheduledLine>> _byStop;

  bool get isEmpty => _byStop.isEmpty;

  int get length => _byStop.length;

  List<ScheduledLine> at(int stopId) => _byStop[stopId] ?? const [];
}

GtfsSchedules parseGtfsSchedules(String text) {
  final byStop = <int, List<ScheduledLine>>{};
  for (final row in const LineSplitter().convert(text)) {
    if (row.isEmpty || row.startsWith('#')) continue;
    final parts = row.split('\t');
    if (parts.length < 6) continue;

    final signage = parts[0].trim();
    final direction = int.tryParse(parts[1].trim());
    if (signage.isEmpty || direction == null) continue;

    final windows = <ServiceWindow>[];
    for (final window in parts[5].split(',')) {
      final at = window.indexOf(':');
      final dash = window.indexOf('-');
      if (at < 0 || dash < 0 || dash > at) continue;
      final start = int.tryParse(window.substring(0, dash));
      final end = int.tryParse(window.substring(dash + 1, at));
      final headway = int.tryParse(window.substring(at + 1));
      if (start == null || end == null || headway == null) continue;
      windows.add(ServiceWindow(
        startMinute: start,
        endMinute: end,
        headwaySeconds: headway,
      ));
    }
    if (windows.isEmpty) continue;

    for (final entry in parts[4].split(',')) {
      final at = entry.indexOf(':');
      if (at < 0) continue;
      final stopId = int.tryParse(entry.substring(0, at));
      final offset = int.tryParse(entry.substring(at + 1));
      if (stopId == null || offset == null) continue;
      (byStop[stopId] ??= []).add(ScheduledLine(
        signage: signage,
        directionId: direction,
        headsign: parts[2].trim(),
        serviceDays: parts[3].trim(),
        offsetMinutes: offset,
        windows: windows,
      ));
    }
  }
  return GtfsSchedules(byStop);
}

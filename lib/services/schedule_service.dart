import 'package:flutter/services.dart' show rootBundle;

import 'gtfs_schedules.dart';
import 'parse_off_thread.dart';
import 'stops_store.dart';

class StopSchedule {
  const StopSchedule({required this.line, required this.window});

  final ScheduledLine line;
  final ServiceWindow? window;

  String get signage => line.signage;

  String get headsign => line.headsign;

  bool get running => window != null;

  String get label {
    final window = this.window;
    if (window != null) return 'about every ${window.headwayMinutes} min';
    return line.runsOn(DateTime.now())
        ? 'not running at this hour'
        : 'does not run today';
  }
}

class ScheduleService {
  ScheduleService({TextLoader? schedulesLoader})
    : _schedulesLoader = schedulesLoader ?? _loadBundledSchedules;

  static const schedulesAsset = 'assets/gtfs/schedules.txt';

  final TextLoader _schedulesLoader;

  GtfsSchedules? _schedules;
  Future<GtfsSchedules>? _loading;

  bool get isLoaded => _schedules != null;

  bool get hasSchedules => _schedules?.isEmpty == false;

  Future<GtfsSchedules> load() {
    final schedules = _schedules;
    if (schedules != null) return Future.value(schedules);
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<List<StopSchedule>> at(int stopCode, {DateTime? now}) async {
    final when = now ?? DateTime.now();
    final lines = (await load()).at(stopCode);
    final schedules = [
      for (final line in lines)
        StopSchedule(line: line, window: line.windowAt(when)),
    ];
    schedules.sort((a, b) {
      if (a.running != b.running) return a.running ? -1 : 1;
      final byHeadway = (a.window?.headwayMinutes ?? 1 << 30).compareTo(
        b.window?.headwayMinutes ?? 1 << 30,
      );
      return byHeadway != 0 ? byHeadway : a.signage.compareTo(b.signage);
    });
    return schedules;
  }

  Future<GtfsSchedules> _load() async {
    GtfsSchedules parsed;
    try {
      final text = await _schedulesLoader();
      parsed = text == null || text.isEmpty
          ? GtfsSchedules.empty
          : await parseOffThread(text, parseGtfsSchedules);
    } catch (_) {
      parsed = GtfsSchedules.empty;
    }
    _schedules = parsed;
    return parsed;
  }

  static Future<String?> _loadBundledSchedules() async {
    try {
      return await rootBundle.loadString(schedulesAsset);
    } catch (_) {
      return null;
    }
  }
}

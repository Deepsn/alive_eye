import 'package:alive_eye/services/gtfs_schedules.dart';
import 'package:alive_eye/services/schedule_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 1012-10 leaves its first stop every 20 min from 05:00 (300) to 05:59 (359)
  // and every 10 min from 06:00 (360) to 09:59 (599). Stop 301724 is 2 min in,
  // stop 301763 is 52 min in. 8000-10 only runs at weekends.
  const asset =
      '# alive_eye schedules v1\n'
      '1012-10\t0\tJd. Monte Belo\t1111111\t301790:0,301724:2,301763:52\t'
      '300-359:1200,360-599:600\n'
      '8000-10\t1\tTerm. Pinheiros\t0000011\t301724:0\t420-1080:900\n';

  ScheduleService serviceWith([String text = asset]) =>
      ScheduleService(schedulesLoader: () async => text);

  // 2026-09-03 is a Thursday, 2026-09-05 a Saturday.
  DateTime thursday(int hour, int minute) => DateTime(2026, 9, 3, hour, minute);
  DateTime saturday(int hour, int minute) => DateTime(2026, 9, 5, hour, minute);

  test('parses a stop into every line that serves it', () {
    final schedules = parseGtfsSchedules(asset);

    expect(schedules.at(301724).map((line) => line.signage), ['1012-10', '8000-10']);
    expect(schedules.at(301790).single.headsign, 'Jd. Monte Belo');
    expect(schedules.at(301763).single.offsetMinutes, 52);
    expect(schedules.at(999).isEmpty, isTrue);
  });

  test('picks the frequency window covering the trip departure, not the stop', () async {
    final service = serviceWith();

    // A bus at stop 301763 at 06:40 left the terminus at 05:48, inside the
    // 20 min window, even though 06:40 itself falls in the 10 min one.
    final late = await service.at(301763, now: thursday(6, 40));
    expect(late.single.window?.headwayMinutes, 20);

    final early = await service.at(301790, now: thursday(6, 40));
    expect(early.single.window?.headwayMinutes, 10);
  });

  test('reports lines that are outside their service hours', () async {
    final service = serviceWith();
    final schedules = await service.at(301724, now: thursday(23, 0));

    final line = schedules.firstWhere((s) => s.signage == '1012-10');
    expect(line.running, isFalse);
    expect(line.label, 'not running at this hour');
  });

  test('reports lines that do not run today', () async {
    final service = serviceWith();
    final schedules = await service.at(301724, now: thursday(9, 0));

    final weekend = schedules.firstWhere((s) => s.signage == '8000-10');
    expect(weekend.running, isFalse);
    expect(weekend.label, 'does not run today');

    final weekday = schedules.firstWhere((s) => s.signage == '1012-10');
    expect(weekday.running, isTrue);
    expect(weekday.label, 'about every 10 min');
  });

  test('runs the weekend line on a Saturday', () async {
    final service = serviceWith();
    final schedules = await service.at(301724, now: saturday(9, 0));

    expect(schedules.firstWhere((s) => s.signage == '8000-10').running, isTrue);
  });

  test('sorts running lines first, then by headway', () async {
    final service = serviceWith();
    final schedules = await service.at(301724, now: thursday(9, 0));

    expect(schedules.map((s) => s.signage), ['1012-10', '8000-10']);
    expect(schedules.first.running, isTrue);
    expect(schedules.last.running, isFalse);
  });

  test('falls back to no schedules when the asset is missing', () async {
    final service = ScheduleService(schedulesLoader: () async => null);

    expect(await service.at(301724), isEmpty);
    expect(service.hasSchedules, isFalse);
  });

  test('skips malformed rows instead of failing the whole asset', () {
    final schedules = parseGtfsSchedules(
      '# alive_eye schedules v1\n'
      'broken\n'
      '1012-10\tx\tA\t1111111\t1:0\t0-100:600\n'
      '1012-10\t0\tA\t1111111\t1:0\t0-100:600\n',
    );

    expect(schedules.at(1), hasLength(1));
  });
}

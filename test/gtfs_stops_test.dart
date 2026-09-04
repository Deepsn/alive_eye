import 'package:alive_eye/services/gtfs_stops.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses SPTrans stops.txt', () {
    final stops = parseGtfsStops(
      '\uFEFFstop_id,stop_name,stop_desc,stop_lat,stop_lon\n'
      '18848,Afonso Braz B/C,"R AFONSO BRAZ, 100/ R DIOGO JACOME",-23.59,-46.67\r\n'
      '340015329,"Stop with ""quotes""",,-23.60,-46.68\n'
      '\n',
    );

    expect(stops, hasLength(2));
    expect(stops[0].code, 18848);
    expect(stops[0].name, 'Afonso Braz B/C');
    expect(stops[0].address, 'R AFONSO BRAZ, 100/ R DIOGO JACOME');
    expect(stops[0].position.latitude, -23.59);
    expect(stops[1].name, 'Stop with "quotes"');
    expect(stops[1].address, '');
  });

  test('accepts any column order and skips malformed rows', () {
    final stops = parseGtfsStops(
      'stop_lon,stop_lat,stop_id,stop_name\n'
      '-46.6,-23.5,1,A\n'
      'oops,-23.5,2,B\n'
      '-46.7,-23.6,3\n'
      '-46.7,-23.6,4,D\n',
    );

    expect(stops.map((s) => s.code), [1, 4]);
    expect(stops.first.position.longitude, -46.6);
  });

  test('rejects files without the required columns', () {
    expect(() => parseGtfsStops('stop_id,stop_name\n1,A\n'), throwsFormatException);
    expect(parseGtfsStops(''), isEmpty);
  });
}

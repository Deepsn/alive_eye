import 'dart:convert';
import 'dart:io';

import 'package:alive_eye/services/olho_vivo_client.dart';
import 'package:alive_eye/services/stops_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const center = LatLng(-23.5614, -46.6559);
  const payload = [
    {'cp': 10, 'np': 'NEAR', 'ed': 'AV PAULISTA', 'py': -23.5616, 'px': -46.6561},
    {'cp': 12, 'np': '', 'ed': 'R AUGUSTA', 'py': -23.5630, 'px': -46.6570},
    {'cp': 11, 'np': 'FAR', 'ed': 'AV PAULISTA', 'py': -23.5800, 'px': -46.6900},
    {'cp': 13, 'np': 'OTHER SIDE OF TOWN', 'ed': 'X', 'py': -23.8145, 'px': -46.7353},
  ];

  late Directory dir;
  late int downloads;
  late List<String> queries;
  late bool networkDown;

  OlhoVivoClient client() => OlhoVivoClient(
    tokenProvider: () => 'tok',
    httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/Login/Autenticar')) {
        return http.Response('true', 200, headers: {'set-cookie': 'apiCredentials=s'});
      }
      if (networkDown) throw const SocketException('offline');
      downloads++;
      queries.add(request.url.query);
      return http.Response(jsonEncode(payload), 200);
    }),
  );

  StopsStore store({Duration maxAge = const Duration(days: 7), String? gtfs}) => StopsStore(
    olhoVivo: client(),
    directory: () async => dir,
    gtfsLoader: () async => gtfs,
    maxAge: maxAge,
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('alive_eye_test');
    downloads = 0;
    queries = [];
    networkDown = false;
  });

  tearDown(() => dir.delete(recursive: true));

  test('downloads the full list with an empty termosBusca', () async {
    final stops = await store().load();

    expect(stops, hasLength(4));
    expect(queries, ['termosBusca=']);
    expect(stops[1].displayName, 'R AUGUSTA');
  });

  test('downloads once per session and reuses the file across instances', () async {
    final first = store();
    await first.load();
    await first.load();
    await store().load();

    expect(downloads, 1);
    expect(File('${dir.path}${Platform.pathSeparator}sptrans_stops.json').existsSync(), isTrue);
  });

  test('nearby filters by radius and sorts by distance', () async {
    final result = await store().nearby(center, 500);

    expect(result.map((s) => s.stop.code), [10, 12]);
    expect(result.every((s) => s.distanceMeters <= 500), isTrue);
  });

  test('nearby measures distance from measureFrom and honours limit', () async {
    const user = LatLng(-23.5632, -46.6572);
    final result = await store().nearby(center, 500, measureFrom: user, limit: 1);

    expect(result.single.stop.code, 12);
    expect(result.single.distanceMeters, lessThan(50));
  });

  test('re-downloads a stale file, but falls back to it when offline', () async {
    await store().load();
    networkDown = true;

    final stale = await store(maxAge: Duration.zero).load();

    expect(stale, hasLength(4));
    expect(downloads, 1);
  });

  test('refresh forces a new download', () async {
    final s = store();
    await s.load();
    await s.load(refresh: true);

    expect(downloads, 2);
  });

  test('propagates auth failures when nothing is cached', () async {
    final s = StopsStore(
      olhoVivo: OlhoVivoClient(
        tokenProvider: () => null,
        httpClient: MockClient((_) async => http.Response('', 500)),
      ),
      directory: () async => dir,
      gtfsLoader: () async => null,
    );

    expect(s.load(), throwsA(isA<OlhoVivoAuthException>()));
  });

  group('with bundled GTFS', () {
    const gtfs =
        'stop_id,stop_name,stop_desc,stop_lat,stop_lon\n'
        '10,Near (GTFS),R GTFS,-23.5616,-46.6561\n'
        '99,East Zone,R LESTE,-23.5170,-46.3980\n';

    test('merges GTFS with the API list, GTFS winning on conflicts', () async {
      final s = store(gtfs: gtfs);
      final stops = await s.load();

      expect(s.hasFullCoverage, isTrue);
      expect(stops.map((x) => x.code), unorderedEquals([10, 12, 11, 13, 99]));
      expect(stops.singleWhere((x) => x.code == 10).name, 'Near (GTFS)');
    });

    test('still works when the API is unreachable', () async {
      networkDown = true;
      final stops = await store(gtfs: gtfs).load();

      expect(stops.map((x) => x.code), [10, 99]);
    });

    test('reports partial coverage without GTFS', () async {
      final s = store();
      await s.load();

      expect(s.hasFullCoverage, isFalse);
    });
  });
}

import 'dart:convert';

import 'package:alive_eye/services/olho_vivo_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('extractCookieHeader', () {
    test('keeps only the name=value pair', () {
      expect(
        extractCookieHeader('apiCredentials=abc123; path=/; HttpOnly'),
        'apiCredentials=abc123',
      );
    });

    test('splits joined cookies without breaking Expires dates', () {
      expect(
        extractCookieHeader(
          'a=1; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/,b=2; Path=/',
        ),
        'a=1; b=2',
      );
    });

    test('returns null when nothing usable is present', () {
      expect(extractCookieHeader(null), isNull);
      expect(extractCookieHeader(''), isNull);
    });
  });

  group('OlhoVivoClient', () {
    late int logins;
    late bool sessionValid;
    late List<String?> cookiesSeen;
    late List<String> searchQueries;
    late OlhoVivoClient client;

    setUp(() {
      logins = 0;
      sessionValid = false;
      cookiesSeen = [];
      searchQueries = [];
      client = OlhoVivoClient(
        tokenProvider: () => 'tok',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/Login/Autenticar')) {
            expect(request.method, 'POST');
            expect(request.url.queryParameters['token'], 'tok');
            logins++;
            sessionValid = true;
            return http.Response(
              'true',
              200,
              headers: {'set-cookie': 'apiCredentials=session$logins; path=/'},
            );
          }

          cookiesSeen.add(request.headers['cookie']);
          if (!sessionValid) return http.Response('denied', 401);

          if (request.url.path.endsWith('/Parada/Buscar')) {
            searchQueries.add(request.url.query);
            return http.Response(
              jsonEncode([
                {'cp': 1, 'np': 'PARADA X', 'ed': 'R Y', 'py': -23.5, 'px': -46.6},
              ]),
              200,
            );
          }
          if (request.url.path.endsWith('/Previsao/Parada')) {
            return http.Response(
              jsonEncode({
                'hr': '10:00',
                'p': {
                  'cp': 1,
                  'np': 'PARADA X',
                  'py': -23.5,
                  'px': -46.6,
                  'l': [
                    {
                      'c': '8000-10',
                      'cl': 123,
                      'sl': 1,
                      'lt0': 'TERMINAL A',
                      'lt1': 'TERMINAL B',
                      'qv': 1,
                      'vs': [
                        {
                          'p': '55555',
                          't': '10:07',
                          'a': true,
                          'ta': '2026-09-03T13:00:00Z',
                          'py': -23.51,
                          'px': -46.61,
                        },
                      ],
                    },
                  ],
                },
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/Posicao/Linha')) {
            return http.Response(
              jsonEncode({
                'hr': '15:14',
                'vs': [
                  {'p': '11056', 'a': true, 'ta': '2026-09-03T18:14:50Z', 'py': -23.48, 'px': -46.72, 'sv': null, 'is': null},
                ],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/Previsao/Linha')) {
            return http.Response(
              jsonEncode({
                'hr': '15:14',
                'ps': [
                  {
                    'cp': 640000459,
                    'np': '',
                    'py': -23.482,
                    'px': -46.718,
                    'vs': [
                      {'p': '11057', 't': '15:28', 'a': true, 'ta': '', 'py': -23.51, 'px': -46.70},
                    ],
                  },
                ],
              }),
              200,
            );
          }
          return http.Response('not found', 404);
        }),
      );
    });

    test('parses line positions and per-stop line forecasts', () async {
      final positions = await client.linePositions(34200);
      final forecast = await client.lineStopsForecast(34200);

      expect(positions.referenceTime, '15:14');
      expect(positions.vehicles.single.prefix, 11056);
      expect(positions.vehicles.single.reportedAt, isNotNull);
      expect(forecast.stops.single.stop.code, 640000459);
      expect(forecast.stopByCode(640000459)?.vehicles.single.etaMinutes, 14);
      expect(forecast.stopByCode(1), isNull);
    });

    test('logs in once and sends the session cookie', () async {
      final stops = await client.searchStops('Paulista');

      expect(stops.single.code, 1);
      expect(stops.single.position.latitude, -23.5);
      expect(logins, 1);
      expect(cookiesSeen, ['apiCredentials=session1']);
    });

    test('re-authenticates and retries once on 401', () async {
      await client.searchStops('Paulista');
      sessionValid = false;

      final stops = await client.searchStops('Augusta');

      expect(stops, hasLength(1));
      expect(logins, 2);
      expect(cookiesSeen.last, 'apiCredentials=session2');
    });

    test('allStopsJson sends an empty termosBusca and returns the raw body', () async {
      final json = await client.allStopsJson();

      expect(jsonDecode(json), hasLength(1));
      expect(searchQueries, ['termosBusca=']);
    });

    test('parallel calls share a single login', () async {
      await Future.wait([
        client.searchStops('a'),
        client.searchStops('b'),
        client.stopForecast(1),
      ]);

      expect(logins, 1);
    });

    test('parses the stop forecast', () async {
      final forecast = await client.stopForecast(1);

      expect(forecast, isNotNull);
      final line = forecast!.lines.single;
      expect(line.signage, '8000-10');
      expect(line.destination, 'TERMINAL A');
      expect(line.vehicles.single.prefix, 55555);
      expect(line.vehicles.single.etaMinutes, 7);
      expect(line.vehicles.single.accessible, isTrue);
    });

    test('throws OlhoVivoAuthException without a token', () async {
      final noToken = OlhoVivoClient(
        tokenProvider: () => null,
        httpClient: MockClient((_) async => http.Response('', 500)),
      );

      expect(noToken.searchStops('x'), throwsA(isA<OlhoVivoAuthException>()));
    });

    test('throws OlhoVivoAuthException when SPTrans rejects the token', () async {
      final rejected = OlhoVivoClient(
        tokenProvider: () => 'bad',
        httpClient: MockClient((_) async => http.Response('false', 200)),
      );

      expect(rejected.searchStops('x'), throwsA(isA<OlhoVivoAuthException>()));
    });
  });
}

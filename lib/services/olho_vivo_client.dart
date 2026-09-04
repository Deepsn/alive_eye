import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/bus_line.dart';
import '../models/bus_stop.dart';
import '../models/line_stops_forecast.dart';
import '../models/stop_forecast.dart';
import '../models/vehicle_position.dart';

typedef TokenProvider = FutureOr<String?> Function();

class OlhoVivoException implements Exception {
  const OlhoVivoException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OlhoVivoAuthException extends OlhoVivoException {
  const OlhoVivoAuthException(super.message);
}

class OlhoVivoClient {
  OlhoVivoClient({
    required this._tokenProvider,
    http.Client? httpClient,
    this._baseUrl = AppConfig.olhoVivoBaseUrl,
  }) : _http = httpClient ?? http.Client();

  final TokenProvider _tokenProvider;
  final http.Client _http;
  final String _baseUrl;

  String? _cookie;
  Future<void>? _loginInFlight;

  Future<List<BusStop>> searchStops(String terms) async {
    final json = await _getJson('Parada/Buscar', {'termosBusca': terms});
    return parseStops(json);
  }

  // An empty termosBusca returns the API's whole stop table (corridor stops only).
  Future<String> allStopsJson() => _getText('Parada/Buscar', {'termosBusca': ''});

  Future<List<BusStop>> stopsForLine(int lineCode) async {
    final json = await _getJson('Parada/BuscarParadasPorLinha', {'codigoLinha': '$lineCode'});
    return parseStops(json);
  }

  Future<List<BusStop>> stopsForCorridor(int corridorCode) async {
    final json = await _getJson('Parada/BuscarParadasPorCorredor', {'codigoCorredor': '$corridorCode'});
    return parseStops(json);
  }

  Future<List<BusLine>> searchLines(String terms) async {
    final json = await _getJson('Linha/Buscar', {'termosBusca': terms});
    return [
      for (final item in json as List)
        BusLine.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<StopForecast?> stopForecast(int stopCode) async {
    final json = await _getJson('Previsao/Parada', {'codigoParada': '$stopCode'});
    return StopForecast.fromJson(json as Map<String, dynamic>);
  }

  Future<LineStopsForecast> lineStopsForecast(int lineCode) async {
    final json = await _getJson('Previsao/Linha', {'codigoLinha': '$lineCode'});
    return LineStopsForecast.fromJson(json as Map<String, dynamic>);
  }

  Future<LinePositions> linePositions(int lineCode) async {
    final json = await _getJson('Posicao/Linha', {'codigoLinha': '$lineCode'});
    return LinePositions.fromJson(json as Map<String, dynamic>);
  }

  static List<BusStop> parseStops(Object? json) => [
    for (final item in json as List)
      BusStop.fromJson(item as Map<String, dynamic>),
  ];

  void resetSession() => _cookie = null;

  void close() => _http.close();

  Future<void> _ensureSession() {
    if (_cookie != null) return Future<void>.value();
    return _loginInFlight ??= _login().whenComplete(() => _loginInFlight = null);
  }

  Future<void> _login() async {
    final token = (await _tokenProvider())?.trim();
    if (token == null || token.isEmpty) {
      throw const OlhoVivoAuthException('No SPTrans API token configured.');
    }

    final response = await _http.post(
      _uri('Login/Autenticar', {'token': token}),
      headers: _headers(),
    );
    if (response.statusCode != 200 || response.body.trim() != 'true') {
      throw const OlhoVivoAuthException('SPTrans rejected the API token.');
    }

    final cookie = extractCookieHeader(response.headers['set-cookie']);
    if (cookie == null) {
      throw const OlhoVivoException('Login succeeded but no session cookie was returned.');
    }
    _cookie = cookie;
  }

  Future<Object?> _getJson(String path, Map<String, String> query) async =>
      jsonDecode(await _getText(path, query));

  Future<String> _getText(String path, Map<String, String> query) async {
    await _ensureSession();
    var response = await _http.get(_uri(path, query), headers: _headers());

    if (response.statusCode == 401) {
      _cookie = null;
      await _ensureSession();
      response = await _http.get(_uri(path, query), headers: _headers());
    }
    if (response.statusCode != 200) {
      throw OlhoVivoException('SPTrans returned HTTP ${response.statusCode} for $path.');
    }
    return utf8.decode(response.bodyBytes);
  }

  // Uri.replace drops the "=" of empty values, but SPTrans needs "termosBusca=".
  Uri _uri(String path, Map<String, String> query) {
    final pairs = [
      for (final MapEntry(:key, :value) in query.entries)
        '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}',
    ];
    return Uri.parse('$_baseUrl/$path?${pairs.join('&')}');
  }

  Map<String, String> _headers() => {
    'User-Agent': AppConfig.userAgent,
    'Accept': 'application/json',
    'Cookie': ?_cookie,
  };
}

// dart:io joins multiple Set-Cookie headers with commas, which also appear
// inside `Expires=Wed, 21 Oct ...`; only split on commas that start a new pair.
String? extractCookieHeader(String? setCookie) {
  if (setCookie == null || setCookie.isEmpty) return null;
  final pairs = setCookie
      .split(RegExp(r',(?=\s*[^;,=\s]+=)'))
      .map((cookie) => cookie.split(';').first.trim())
      .where((pair) => pair.contains('='))
      .toList();
  return pairs.isEmpty ? null : pairs.join('; ');
}

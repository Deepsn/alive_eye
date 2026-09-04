import 'package:latlong2/latlong.dart';

abstract final class AppConfig {
  static const olhoVivoToken = String.fromEnvironment('OLHO_VIVO_TOKEN');
  static const olhoVivoBaseUrl = 'https://api.olhovivo.sptrans.com.br/v2.1';
  static const developerPortalUrl = 'https://www.sptrans.com.br/desenvolvedores/';
  static const userAgent = 'alive_eye/1.0 (Flutter)';
  static const packageName = 'io.github.deepsn.alive_eye';
  static const appName = 'Alive Eye';
  static const notificationGuid = '9f2c7b48-1d3a-4e56-8b07-6a5d9c1e4f20';

  static const fallbackCenter = LatLng(-23.5503, -46.6339);
}

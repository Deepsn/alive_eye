import 'package:flutter/material.dart';

import 'screens/map_screen.dart';
import 'services/arrival_alerts.dart';
import 'services/line_route_service.dart';
import 'services/notifications.dart';
import 'services/olho_vivo_client.dart';
import 'services/schedule_service.dart';
import 'services/stops_store.dart';
import 'services/token_store.dart';

void main() {
  runApp(const AliveEyeApp());
}

class AliveEyeApp extends StatefulWidget {
  const AliveEyeApp({super.key});

  @override
  State<AliveEyeApp> createState() => _AliveEyeAppState();
}

class _AliveEyeAppState extends State<AliveEyeApp> {
  final _tokenStore = TokenStore();
  late final _client = OlhoVivoClient(tokenProvider: _tokenStore.read);
  late final _stops = StopsStore(olhoVivo: _client);
  late final _routes = LineRouteService(stopsByCode: _stops.byCode);
  late final _alerts = ArrivalAlerts(client: _client, notifier: LocalNotifier());
  final _schedules = ScheduleService();

  @override
  void initState() {
    super.initState();
    _alerts.restore();
  }

  @override
  void dispose() {
    _alerts.dispose();
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alive Eye',
      theme: ThemeData(
        colorScheme: .fromSeed(seedColor: const Color(0xFFB71C1C)),
      ),
      home: MapScreen(
        client: _client,
        stops: _stops,
        routes: _routes,
        tokenStore: _tokenStore,
        alerts: _alerts,
        schedules: _schedules,
      ),
    );
  }
}

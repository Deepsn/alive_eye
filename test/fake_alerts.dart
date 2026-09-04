import 'package:alive_eye/services/alert_store.dart';
import 'package:alive_eye/services/arrival_alerts.dart';
import 'package:alive_eye/services/notifications.dart';
import 'package:alive_eye/services/olho_vivo_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeNotifier implements Notifier {
  FakeNotifier({this.allowed = true});

  bool allowed;
  final shown = <(int, String, String)>[];

  @override
  Future<bool> enable() async => allowed;

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async => shown.add((id, title, body));
}

class MemoryAlertStore implements AlertStore {
  List<AlertTarget> saved = const [];

  @override
  Future<List<AlertTarget>> read() async => saved;

  @override
  Future<void> write(Iterable<AlertTarget> targets) async => saved = [...targets];
}

({ArrivalAlerts alerts, FakeNotifier notifier, MemoryAlertStore store}) fakeAlerts({
  OlhoVivoClient? client,
  bool allowed = true,
}) {
  final notifier = FakeNotifier(allowed: allowed);
  final store = MemoryAlertStore();
  final alerts = ArrivalAlerts(
    client:
        client ??
        OlhoVivoClient(
          tokenProvider: () => 'tok',
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        ),
    notifier: notifier,
    store: store,
  );
  addTearDown(alerts.dispose);
  return (alerts: alerts, notifier: notifier, store: store);
}

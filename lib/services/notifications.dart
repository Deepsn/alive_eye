import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/app_config.dart';

abstract interface class Notifier {
  Future<bool> enable();

  Future<void> show({required int id, required String title, required String body});
}

class LocalNotifier implements Notifier {
  LocalNotifier({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const channelId = 'arrivals';

  static const _settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    windows: WindowsInitializationSettings(
      appName: AppConfig.appName,
      appUserModelId: AppConfig.packageName,
      guid: AppConfig.notificationGuid,
    ),
  );

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      'Bus arrivals',
      channelDescription: 'Fires when a bus is close to a stop you follow.',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    ),
    windows: WindowsNotificationDetails(),
  );

  final FlutterLocalNotificationsPlugin _plugin;
  bool _started = false;

  @override
  Future<bool> enable() async {
    if (!_started) {
      if (await _plugin.initialize(settings: _settings) == false) return false;
      _started = true;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    return await android.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> show({required int id, required String title, required String body}) =>
      _plugin.show(id: id, title: title, body: body, notificationDetails: _details);
}

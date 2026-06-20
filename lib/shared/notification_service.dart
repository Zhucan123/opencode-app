import 'dart:typed_data';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final _localNotifications = FlutterLocalNotificationsPlugin();
bool _localNotificationsReady = false;

class NotificationService {
  static Future<void> init() async {
    // 初始化前台服务配置
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'opencode_connection',
        channelName: 'opencode 连接',
        channelDescription: 'opencode SSH 连接保活',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
      ),
    );

    // 初始化本地通知（AI 回复完成用）
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit),
    );
    _localNotificationsReady = true;
  }

  static Future<void> startForeground(String serverName) async {
    final hasPermission = await FlutterForegroundTask.checkNotificationPermission();
    if (hasPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      serviceId: 1001,
      notificationTitle: 'opencode 已连接',
      notificationText: serverName,
    );
  }

  static Future<void> updateForeground(String serverName, {String? subtitle}) async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: subtitle ?? 'opencode 已连接',
      notificationText: serverName,
    );
  }

  static Future<void> stopForeground() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  static Future<void> notifyAiComplete(String sessionTitle) async {
    if (!_localNotificationsReady) return;
    final vibrationPattern = Int64List.fromList([0, 300, 100, 300]);
    final details = AndroidNotificationDetails(
      'ai_complete_native',
      'AI 回复完成',
      channelDescription: 'opencode AI 完成回复时弹出横幅并振动',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      vibrationPattern: vibrationPattern,
      playSound: true,
      autoCancel: true,
    );
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF,
      'AI 回复完成',
      sessionTitle,
      NotificationDetails(android: details),
    );
  }
}

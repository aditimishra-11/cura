import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  // FCM shows background notifications automatically via the system
}

class NotificationService {
  static final _messaging = FirebaseMessaging.instance;
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static const _channelId = 'cura_reminders';
  static const _channelName = 'Cura Reminders';

  static Future<void> init() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

    // Initialise flutter_local_notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings),
    );

    // Create a high-importance notification channel for Android 8+
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Reminder and digest push notifications',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Show a heads-up banner when a push arrives while the app is in the foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification == null) return;
      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    });

    // Register FCM token with backend
    final token = await _messaging.getToken();
    if (token != null) await _registerToken(token);
    _messaging.onTokenRefresh.listen(_registerToken);
  }

  static Future<void> _registerToken(String token) async {
    try {
      await ApiService.registerDevice(token);
    } catch (_) {}
  }

  /// Call this after Google sign-in to re-register the current token with
  /// the user's email attached, so reminders go to the right device.
  static Future<void> reRegister() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) await _registerToken(token);
    } catch (_) {}
  }
}

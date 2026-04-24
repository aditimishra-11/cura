import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  // FCM shows background notifications automatically
}

class NotificationService {
  static final _messaging = FirebaseMessaging.instance;

  static Future<void> init() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

    final token = await _messaging.getToken();
    if (token != null) await _registerToken(token);

    _messaging.onTokenRefresh.listen(_registerToken);
  }

  static Future<void> _registerToken(String token) async {
    try {
      final base = await ApiService.getBaseUrl();
      await http.post(
        Uri.parse('$base/register-device'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fcm_token': token}),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }
}

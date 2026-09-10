import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('FCM background message: ${message.messageId}');
}

class PushNotificationService {
  PushNotificationService._();

  static Future<String?> initialize() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('Push notifications: user declined permission.');
      return null;
    }

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('FCM foreground message: ${message.notification?.title}');
    });

    final token = await FirebaseMessaging.instance.getToken();
    debugPrint('FCM token: $token');
    return token;
  }
}
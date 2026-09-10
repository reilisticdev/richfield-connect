// mobile/lib/services/push_notification_service.dart
//
// FCM plumbing: permission + token + background handler, PLUS persisting
// that token to profiles.fcm_token so something server-side can actually
// target this device. initialize() alone (device/OS-level, permission +
// token) previously only debugPrint()'d the token — nothing wrote it
// anywhere, so supabase/functions/send-push-notification had a column to
// read from that would always be null. syncTokenIfSignedIn() is the other
// half that makes the migration and Edge Function not pointless.
//
// syncTokenIfSignedIn() is deliberately NOT called from initialize(), and
// initialize() is deliberately NOT the place doing the Supabase write.
// initialize() runs in main() before Supabase.initialize() and before any
// user is signed in — there is no profile row to write to yet at that
// point. The write has to happen after auth state is known, so it's wired
// separately in main.dart to Supabase's onAuthStateChange stream (the
// same stream GoRouterRefreshStream already listens to).

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('FCM background message: ${message.messageId}');
}

class PushNotificationService {
  PushNotificationService._();

  /// Call once at startup, after Firebase.initializeApp(). Requests the
  /// notification permission and returns the device's FCM token (null if
  /// the user declined).
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

    // Foreground messages don't show in the system tray by default on
    // Android — this at least surfaces them in the console. Rendering an
    // in-app banner/snackbar for a foreground push is UI work, not part
    // of this wiring pass.
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('FCM foreground message: ${message.notification?.title}');
    });

    final token = await FirebaseMessaging.instance.getToken();
    debugPrint('FCM token: $token');
    return token;
  }

  static String? _lastSyncedToken;

  /// Writes the device's current FCM token onto the signed-in user's
  /// profile row. No-op when signed out, when permission was never
  /// granted (getToken() returns null), or when the token hasn't changed
  /// since the last successful write — so this is cheap to call on every
  /// auth state change rather than needing its own trigger logic.
  ///
  /// Best-effort by design: a failed sync must never block sign-in or
  /// navigation. It naturally retries on the next auth state change.
  static Future<void> syncTokenIfSignedIn() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token == _lastSyncedToken) return;

    try {
      await client.from('profiles').update({'fcm_token': token}).eq('id', userId);
      _lastSyncedToken = token;
    } catch (e) {
      debugPrint('FCM token sync failed: $e');
    }
  }
}

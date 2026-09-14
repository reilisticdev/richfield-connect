// mobile/lib/services/current_user_profile.dart
//
// The signed-in member's own name/photo, cached app-wide so RichfieldHeader
// (mounted once per tab, five-plus places) doesn't each need their own
// profile fetch just to render the top-right avatar. Same ValueNotifier
// pattern as RealtimeHub's unread counts - several independent widgets need
// to observe the same fast-changing value, which is exactly the case that
// pattern exists for (see main.dart's state-management notes).
//
// Refreshed from the same auth-state-change hook that already drives
// PushNotificationService.syncTokenIfSignedIn(), so it updates on sign-in,
// sign-out (falls back to the generic icon) and token refresh alike, and
// again right after a successful avatar upload in EditProfileScreen so the
// header doesn't wait for the next auth event to catch up.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CurrentUserProfileData {
  const CurrentUserProfileData({required this.firstName, required this.lastName, this.avatarPath});

  final String firstName;
  final String lastName;
  final String? avatarPath;
}

class CurrentUserProfile {
  CurrentUserProfile._();

  static final ValueNotifier<CurrentUserProfileData?> data =
      ValueNotifier<CurrentUserProfileData?>(null);

  static Future<void> refresh() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      data.value = null;
      return;
    }
    try {
      final row = await client
          .from('profiles')
          .select('first_name, last_name, avatar_path')
          .eq('id', uid)
          .single();
      data.value = CurrentUserProfileData(
        firstName: (row['first_name'] as String?) ?? '',
        lastName: (row['last_name'] as String?) ?? '',
        avatarPath: row['avatar_path'] as String?,
      );
    } catch (_) {
      // Best-effort: the header just keeps showing whatever it had before
      // (or the generic icon on first load), same as a missed FCM sync.
    }
  }
}

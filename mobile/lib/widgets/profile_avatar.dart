// mobile/lib/widgets/profile_avatar.dart
//
// A member's photo when they have one, their initials when they don't.
// Shared by the Network, Messages, Chat, Notifications and member profile
// screens.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart' show AppColors, AppText;
import '../services/media_service.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.firstName,
    required this.lastName,
    this.avatarPath,
    this.radius = 20,
  });

  final String? firstName;
  final String? lastName;
  final String? avatarPath;
  final double radius;

  static String initialsOf(String? first, String? last) {
    final f = (first ?? '').trim();
    final l = (last ?? '').trim();
    final initials = (f.isEmpty ? '' : f[0]) + (l.isEmpty ? '' : l[0]);
    return initials.isEmpty ? '?' : initials.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final path = avatarPath?.trim() ?? '';
    // The plain public URL, deliberately without MediaService.avatarUrl()'s
    // cache-buster: that exists so your own just-edited photo refreshes, but
    // in a list it would re-download every avatar on every rebuild.
    final url = path.isEmpty
        ? null
        : Supabase.instance.client.storage.from(MediaService.avatarsBucket).getPublicUrl(path);

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.secondaryContainer,
      foregroundImage: url == null ? null : NetworkImage(url),
      onForegroundImageError: url == null ? null : (_, __) {},
      child: Text(
        initialsOf(firstName, lastName),
        style: AppText.labelLg(color: AppColors.onSecondaryContainer).copyWith(fontSize: radius * 0.7),
      ),
    );
  }
}

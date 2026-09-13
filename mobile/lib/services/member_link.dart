// mobile/lib/services/member_link.dart
//
// QR Connect: the Portfolio shows a QR code of richfield://member/<uid>, and
// scanning it with a phone camera opens that member's profile in the app
// (AndroidManifest: the richfield scheme with host "member"). Bonus feature
// for career fairs and campus events — trade a scan instead of typing a
// name into the Network search.
//
// Delivery mirrors services/email_confirmation.dart: app_links hands over
// every richfield:// URI (including the one that cold-started the app),
// this file keeps the parsed profile id in a ValueNotifier, and the
// signed-in shell (RootShell) is what actually pushes MemberProfileScreen
// — the same Navigator.push the Network, chat, notifications and career
// pathway screens use. Not a GoRoute on purpose: flutter_deeplinking_enabled
// is off (see the manifest), and go('/member/<id>') would replace the
// tab shell instead of opening the profile over it. If the link arrives
// while signed out, the id waits until the shell mounts after sign-in.

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

class MemberLink {
  MemberLink._();

  static const scheme = 'richfield';
  static const host = 'member';

  /// Profile id from a richfield://member/<uid> link that hasn't been
  /// opened yet. Cleared by RootShell once it pushes the profile.
  static final ValueNotifier<String?> pendingProfileId = ValueNotifier<String?>(null);

  static bool _listening = false;

  /// The link the QR code encodes for [profileId].
  static String linkFor(String profileId) => '$scheme://$host/$profileId';

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  /// The profile id in [uri], or null when it isn't a member link or the id
  /// isn't a UUID (profiles.id). A scanned code is untrusted input: this is
  /// the only thing that reaches a query, and it only ever reaches
  /// MemberProfileScreen, which RLS filters like any other profile view.
  static String? profileIdFrom(Uri uri) {
    if (uri.scheme != scheme || uri.host != host) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length != 1) return null;
    final id = segments.single.toLowerCase();
    return _uuid.hasMatch(id) ? id : null;
  }

  /// Watches for member links, including the one that cold-started the
  /// app. Safe to call more than once.
  static Future<void> listenForDeepLink() async {
    if (_listening) return;
    _listening = true;
    final links = AppLinks();
    try {
      final initial = await links.getInitialLink();
      if (initial != null) _onLink(initial);
    } catch (_) {
      // No initial link, or the platform couldn't read it. Nothing to do.
    }
    links.uriLinkStream.listen(_onLink, onError: (_) {});
  }

  static void _onLink(Uri uri) {
    final id = profileIdFrom(uri);
    if (id != null) pendingProfileId.value = id;
  }

  /// Takes the pending id, if any, leaving nothing behind.
  static String? consumePending() {
    final id = pendingProfileId.value;
    pendingProfileId.value = null;
    return id;
  }
}

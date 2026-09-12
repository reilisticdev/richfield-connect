// mobile/lib/services/email_confirmation.dart
//
// The moment a member's email is confirmed, the app says so — instead of a
// browser tab sitting on http://localhost:3000 (Keshav's QA, 2026-09-12).
//
// Two ways in, both ending in a signed-in session and a one-time welcome:
//   1. The 6-digit code in the confirmation email, typed on the "Check your
//      inbox" screen (AuthService.verifySignupCode). Works whichever device
//      the email is read on; no browser involved.
//   2. The link in the email, tapped on the phone. GoTrue verifies it and
//      redirects to the email-confirmed edge function, which sends phones
//      to richfield://auth/confirmed?code=…; supabase_flutter exchanges the
//      PKCE code for a session on its own. This file only notices that the
//      app was opened by that link, so the shell can show the welcome.
//
// Neither path creates a session on a laptop: the code verifier lives on the
// phone that registered, and the function shows plain text there instead.

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../main.dart' show AppColors;

class EmailConfirmation {
  EmailConfirmation._();

  /// Set when the app was opened by the confirmation link or the code was
  /// verified in-app. Cleared by whichever signed-in screen shows the
  /// welcome first.
  static final ValueNotifier<bool> justConfirmed = ValueNotifier<bool>(false);

  static bool _listening = false;

  /// Watches for richfield://auth/confirmed, including the link that
  /// cold-started the app. Safe to call more than once.
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
    if (uri.scheme == 'richfield' && uri.host == 'auth' && uri.path == '/confirmed') {
      justConfirmed.value = true;
    }
  }

  /// Shows the welcome once, if one is due. Call after a signed-in screen's
  /// first frame — never from build() directly.
  static Future<void> showWelcomeIfDue(
    BuildContext context, {
    required bool awaitingApproval,
  }) async {
    if (!justConfirmed.value) return;
    justConfirmed.value = false;
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        icon: Icon(Icons.verified_outlined, color: AppColors.primary, size: 40),
        title: Text('Your email is confirmed'),
        content: Text(
          awaitingApproval
              ? 'Welcome to Richfield Connect. A Richfield administrator will now review '
                  'your account; you\'ll be able to use the app as soon as it\'s approved.'
              : 'Welcome to Richfield Connect! Your account is ready. Start with your '
                  'profile so employers and classmates can find you.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(awaitingApproval ? 'OK' : 'Let\'s go'),
          ),
        ],
      ),
    );
  }
}

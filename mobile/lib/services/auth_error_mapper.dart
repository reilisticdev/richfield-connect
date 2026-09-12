// mobile/lib/services/auth_error_mapper.dart
//
// Central place that turns Supabase exceptions into strings the UI can show
// directly. The goal: surface the real Postgres message wherever GoTrue/
// PostgREST actually provides one, instead of a hardcoded generic string.

import 'package:supabase_flutter/supabase_flutter.dart';

class AuthErrorMapper {
  /// Use for anything thrown by AuthService.signUp / signIn / signOut.
  static String fromAuthException(AuthException e) {
    // GoTrue-specific known cases where the message it gives you IS useful.
    switch (e.statusCode) {
      case '400':
        if (e.message.toLowerCase().contains('already registered')) {
          return 'An account with this email already exists.';
        }
        break;
      case '422':
        return e.message; // GoTrue's own validation messages are usually fine as-is
    }

    // This is the case called out in the migrations: a trigger on
    // auth.users (domain restriction, admin self-registration block) raised
    // an exception, and GoTrue collapsed it into a generic 500. If
    // AuthService's client-side pre-check didn't already catch it, this is
    // the best we can surface without a custom Edge Function relay.
    if (e.message.contains('Database error saving new user')) {
      return "We couldn't create that account. Double-check your email is "
          "correct for the account type you selected, then try again.";
    }

    // Migration 033 bans suspended accounts, and GoTrue then refuses sign-in.
    if (e.message.toLowerCase().contains('banned')) {
      return 'This account has been suspended by a Richfield administrator.';
    }

    // Signed up, never confirmed. The login screen adds a "Resend
    // confirmation email" action next to this one.
    if (e.message.toLowerCase().contains('not confirmed')) {
      return 'Confirm your email first: use the 6-digit code or the link we emailed you when you registered.';
    }

    // verifyOTP with a wrong, reused or stale 6-digit code.
    final lower = e.message.toLowerCase();
    if (lower.contains('token has expired') || lower.contains('otp_expired') ||
        (lower.contains('invalid') && lower.contains('token'))) {
      return 'That code isn\'t right or has expired. Check the latest email, or request a new one.';
    }

    if (lower.contains('rate limit') || lower.contains('for security purposes')) {
      return 'Too many emails requested. Wait a minute, then try again.';
    }

    // GoTrue created the account but could not hand the confirmation email
    // to the SMTP provider, so it rolled the sign-up back and returned a
    // 500 whose body the SDK passes through verbatim - the member saw
    // {"code":"unexpected_failure","message":"Error sending confirmation
    // email"} on the register screen (2026-09-12: Resend refused the
    // sender domain configured in Supabase Auth). Nothing they typed is
    // wrong, and re-trying with the same address is fine.
    if (lower.contains('sending confirmation email') ||
        (lower.contains('unexpected_failure') && lower.contains('email'))) {
      return "We couldn't send your confirmation email just now. That's a problem on "
          "our side, not with your details - please try again in a few minutes.";
    }

    return e.message;
  }

  /// Use for anything thrown by direct table calls or RPC calls
  /// (profiles updates, verification_claims inserts,
  /// approve_alumni_verification/reject_alumni_verification). These DO
  /// carry the real Postgres message/detail/hint/code.
  static String fromPostgrestException(PostgrestException e) {
    final parts = <String>[e.message];
    if (e.hint != null && e.hint!.isNotEmpty) {
      parts.add(e.hint!);
    }
    return parts.join(' ');
  }

  /// Convenience for a try/catch that doesn't know which kind it caught.
  static String fromAny(Object error) {
    if (error is AuthException) return fromAuthException(error);
    if (error is PostgrestException) return fromPostgrestException(error);
    return 'Something went wrong. Please try again.';
  }
}

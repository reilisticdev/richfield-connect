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

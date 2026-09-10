// mobile/lib/services/auth_service.dart
//
// Thin wrapper around supabase_flutter's auth client. Kept deliberately
// small: it does not decide what happens on success/failure (screens do
// that), it just performs the call and lets real exceptions propagate so
// the UI layer can map them with AuthErrorMapper.

import 'package:supabase_flutter/supabase_flutter.dart';

/// Allowed self-registration roles. 'administrator' is intentionally
/// excluded — supabase/migrations/005_signup_role_restriction.sql rejects
/// it at the trigger level, and the client should never offer it as an
/// option in the first place.
enum SignupRole { student, alumni, business }

class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;

  /// Stream of auth state changes, used to drive GoRouter's refreshListenable.
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  /// Domains allowed for student self-registration. Mirrors
  /// enforce_student_domain() in 003_domain_restriction.sql.
  ///
  /// IMPORTANT: this check exists here because GoTrue does not forward the
  /// trigger's RAISE EXCEPTION message to the client on signUp — it returns
  /// a generic "Database error saving new user" (500) instead. Checking
  /// client-side first gives the user the real message; the DB trigger
  /// remains the actual security boundary and still runs regardless.
  static const _studentDomains = [
    '@my.richfield.ac.za',
    '@richfield.ac.za',
    '@my.aaa.ac.za',
    '@aaa.ac.za',
  ];

  String? validateStudentEmailDomain(String email) {
    final lower = email.toLowerCase().trim();
    final matches = _studentDomains.any((d) => lower.endsWith(d));
    if (!matches) {
      return 'Students must use a valid Richfield or AAA institutional email address.';
    }
    return null;
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required SignupRole role,
    String? firstName,
    String? lastName,
  }) {
    // Client-side pre-check for the domain rule so the user sees the real
    // message instead of GoTrue's generic 500. See note above.
    if (role == SignupRole.student) {
      final domainError = validateStudentEmailDomain(email);
      if (domainError != null) {
        throw AuthException(domainError);
      }
    }

    return _client.auth.signUp(
      email: email,
      password: password,
      data: {
        'role': role.name, // 'student' | 'alumni' | 'business' — never 'administrator'
        'first_name': firstName,
        'last_name': lastName,
      },
    );
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  /// Sends the GoTrue password-recovery email.
  ///
  /// Deliberately does NOT tell the caller whether the address exists.
  /// GoTrue returns success either way, and the UI must show the same
  /// confirmation regardless — otherwise the "Forgot password" form becomes
  /// an account-enumeration oracle that reveals which student emails are
  /// registered.
  ///
  /// With no redirectTo, the link in the email lands on the project's
  /// configured Site URL. Set a deep link later if the reset should reopen
  /// the app instead of a browser.
  Future<void> sendPasswordReset(String email) {
    return _client.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    _cachedProfile = null;
    _cachedProfileUserId = null;
    _cachedProfileAt = null;
  }

  // GoRouter's redirect callback (app_router.dart) calls fetchOwnProfile()
  // on every navigation. Caching collapses that into one network round trip
  // per _profileCacheTtl window instead of one per tab tap, while still
  // picking up an account_status change (e.g. an admin approving a pending
  // business) within a demo-reasonable window — an infinite cache would
  // silently miss that until the next app restart.
  Map<String, dynamic>? _cachedProfile;
  String? _cachedProfileUserId;
  DateTime? _cachedProfileAt;
  static const _profileCacheTtl = Duration(seconds: 30);

  /// Fetches the caller's own profile row (role, account_status, etc).
  /// Any Postgres-level error here (RLS denial, missing row) surfaces as a
  /// real PostgrestException with message/details/hint/code intact.
  Future<Map<String, dynamic>> fetchOwnProfile() async {
    final userId = currentUser?.id;
    if (userId == null) {
      throw StateError('fetchOwnProfile called with no active session');
    }

    final cachedAt = _cachedProfileAt;
    if (_cachedProfile != null &&
        _cachedProfileUserId == userId &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _profileCacheTtl) {
      return _cachedProfile!;
    }

    final profile = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .single();
    _cachedProfile = profile;
    _cachedProfileUserId = userId;
    _cachedProfileAt = DateTime.now();
    return profile;
  }
}

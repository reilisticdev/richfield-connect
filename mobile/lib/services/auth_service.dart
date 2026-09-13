// mobile/lib/services/auth_service.dart
//
// Thin wrapper around supabase_flutter's auth client. Kept deliberately
// small: it does not decide what happens on success/failure (screens do
// that), it just performs the call and lets real exceptions propagate so
// the UI layer can map them with AuthErrorMapper.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

import 'profile_service.dart';

/// Allowed self-registration roles. 'administrator' is intentionally
/// excluded — supabase/migrations/005_signup_role_restriction.sql rejects
/// it at the trigger level, and the client should never offer it as an
/// option in the first place.
enum SignupRole { student, alumni, business }

class AuthService {
  AuthService(this._client) {
    // GoTrue emits passwordRecovery when a session came from a reset link
    // (the phone deep-link path). The router parks that session on
    // /reset-password until updatePassword() clears the flag.
    _client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) recoveryPending = true;
    }, onError: (_) {});
  }

  final SupabaseClient _client;

  /// True between "signed in from a password-reset link/code" and
  /// "saved a new password". Read by the router's redirect.
  bool recoveryPending = false;

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
    Map<String, Object> details = const {},
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
      // The confirmation link lands on the email-confirmed function (phones
      // are sent on into the app) instead of the default localhost Site URL.
      emailRedirectTo: SupabaseConfig.emailConfirmedUrl,
      data: {
        // Programme, campus, years, student number or company details from
        // the register form. With email confirmation on there is no session
        // to insert those rows with yet, so handle_new_user() (migration 028)
        // writes the education / verification_claims / business_profiles
        // rows from this metadata. Spread first so it can't override role.
        ...details,
        'role': role.name, // 'student' | 'alumni' | 'business' — never 'administrator'
        'first_name': firstName,
        'last_name': lastName,
      },
    );
  }

  /// The 6-digit code from the confirmation email ({{ .Token }} in the
  /// "Confirm signup" template). On success the account is confirmed AND
  /// signed in — no browser, no link, whichever device read the email.
  Future<AuthResponse> verifySignupCode({required String email, required String code}) {
    return _client.auth.verifyOTP(
      type: OtpType.signup,
      email: email.trim(),
      token: code.trim(),
    );
  }

  /// A fresh confirmation email (new code + new link). GoTrue rate-limits
  /// this per address; the error message says so if it's too soon.
  Future<void> resendSignupEmail(String email) {
    return _client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
      emailRedirectTo: SupabaseConfig.emailConfirmedUrl,
    );
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    // A password sign-in is not a recovery, whatever a stale reset link
    // left behind.
    recoveryPending = false;
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
    return _client.auth.resetPasswordForEmail(
      email.trim(),
      // The email-confirmed function reads ?flow=recovery: phones are sent
      // to richfield://auth/recovery, laptops get reset-specific text. If
      // this exact URL isn't allow-listed GoTrue falls back to the Site URL
      // (the same function without the flag) — the phone path still works,
      // only the laptop wording is generic.
      redirectTo: '${SupabaseConfig.emailConfirmedUrl}?flow=recovery',
    );
  }

  /// The 6-digit code from the password-reset email ({{ .Token }} in the
  /// "Reset password" template). Signs the member in so [updatePassword]
  /// can run — no browser, whichever device read the email.
  Future<AuthResponse> verifyRecoveryCode({required String email, required String code}) async {
    final response = await _client.auth.verifyOTP(
      type: OtpType.recovery,
      email: email.trim(),
      token: code.trim(),
    );
    recoveryPending = true;
    return response;
  }

  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
    recoveryPending = false;
  }

  /// Signs out everywhere. If GoTrue refuses the server-side part — the
  /// session was already killed by an administrator's suspend/remove, or
  /// the token has expired — fall back to clearing this device, so the
  /// "Sign out" buttons on the suspended/pending screens and the account
  /// menu always end with no session, never with an exception and a dead
  /// token still on the phone.
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      await signOutLocally();
      return;
    }
    _clearProfileCache();
  }

  /// Clears the session on this device only and never throws. For a
  /// session the server has already invalidated (account removed or
  /// banned), a global signOut() would call GoTrue's /logout and fail,
  /// leaving the dead token in place — which is how the router looped
  /// between /home and /login after an admin removed a test account.
  Future<void> signOutLocally() async {
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // Local scope touches no network; nothing sensible can fail here,
      // and if something did there is nothing better to do than move on.
    }
    _clearProfileCache();
  }

  void _clearProfileCache() {
    recoveryPending = false;
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

    // Explicit columns: `select *` is refused on profiles since migration
    // 037 (email / fcm_token are member-invisible). See ProfileService.
    final profile = await _client
        .from('profiles')
        .select(ProfileService.columns)
        .eq('id', userId)
        .single();
    _cachedProfile = profile;
    _cachedProfileUserId = userId;
    _cachedProfileAt = DateTime.now();
    return profile;
  }
}

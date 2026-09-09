// mobile/lib/router/app_router.dart
//
// GoRouter wired to Supabase's actual auth state, not a placeholder bool.
// Route guards read currentSession + (when needed) the profile's role and
// account_status, so redirects match what the database will actually allow.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
// main.dart imports this file for buildAppRouter(), and this file imports
// main.dart back for the real screen widgets (LoginScreen, RegisterScreen,
// RootShell, RichfieldRole) — a legal, ordinary circular import in Dart.
import '../main.dart';

/// Bridges a Stream to GoRouter's Listenable-based refresh mechanism.
/// This is the standard pattern from the go_router docs — GoRouter needs a
/// Listenable, Supabase gives you a Stream, this adapts one to the other.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

GoRouter buildAppRouter(AuthService authService) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: GoRouterRefreshStream(authService.onAuthStateChange),
    redirect: (context, state) async {
      final loggedIn = authService.currentSession != null;
      final loggingInPaths = {'/login', '/signup'};
      final isGoingToAuth = loggingInPaths.contains(state.matchedLocation);

      // Not logged in and not headed to an auth page -> send to login.
      if (!loggedIn && !isGoingToAuth) {
        return '/login';
      }

      // Logged in and sitting on an auth page -> send into the app.
      if (loggedIn && isGoingToAuth) {
        return '/home';
      }

      // Logged in: check profile-level gates that a session alone doesn't
      // tell you (pending approval, forced MFA setup, admin-only routes).
      if (loggedIn) {
        final user = authService.currentUser!;
        final requiresMfaSetup = user.appMetadata['requires_mfa_setup'] == true;

        if (requiresMfaSetup && state.matchedLocation != '/mfa-setup') {
          return '/mfa-setup';
        }

        // account_status / role live in `profiles`, not the JWT, so this
        // needs an actual fetch. AuthService.fetchOwnProfile() caches this
        // for a short TTL so it isn't a full round trip on every navigation.
        try {
          final profile = await authService.fetchOwnProfile();
          final accountStatus = profile['account_status'] as String?;
          final role = profile['role'] as String?;

          if (accountStatus == 'pending' && state.matchedLocation != '/pending-approval') {
            return '/pending-approval';
          }
          if (accountStatus == 'rejected' && state.matchedLocation != '/account-rejected') {
            return '/account-rejected';
          }
          if (state.matchedLocation.startsWith('/admin') && role != 'administrator') {
            return '/home'; // not an admin — bounce, don't 403 silently
          }
        } on PostgrestException catch (e) {
          // PGRST116 = .single() found zero (or >1) rows: genuinely no
          // profile row exists yet for this signed-in user — treat as
          // not-yet-provisioned. Any other Postgrest error (transient 5xx,
          // a momentary RLS/connection hiccup) must NOT force a logout
          // mid-session — stay on the current route instead.
          if (e.code == 'PGRST116') {
            return '/login';
          }
        } catch (_) {
          // Non-Postgrest failure (e.g. a dropped connection). Same
          // reasoning — don't force a logout over a transient error.
        }
      }

      return null; // no redirect needed
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => LoginScreen(authService: authService)),
      GoRoute(path: '/signup', builder: (context, state) => RegisterScreen(authService: authService)),
      GoRoute(path: '/mfa-setup', builder: (context, state) => const MfaSetupScreenPlaceholder()),
      GoRoute(path: '/pending-approval', builder: (context, state) => const PendingApprovalScreenPlaceholder()),
      GoRoute(path: '/account-rejected', builder: (context, state) => const AccountRejectedScreenPlaceholder()),
      GoRoute(path: '/home', builder: (context, state) => _HomeGate(authService: authService)),
      GoRoute(path: '/admin', builder: (context, state) => const AdminHomeScreenPlaceholder()),
      GoRoute(path: '/', redirect: (context, state) => '/home'),
    ],
  );
}

// role/account_status live in Postgres, not the JWT, and GoRoute.builder is
// synchronous — this fetches the profile once to decide which RichfieldRole
// tab-shell to land on (Feed vs BusinessHub vs AdminHub).
class _HomeGate extends StatelessWidget {
  const _HomeGate({required this.authService});

  final AuthService authService;

  RichfieldRole _roleFromProfile(String? role) {
    switch (role) {
      case 'alumni':
        return RichfieldRole.alumni;
      case 'business':
        return RichfieldRole.corporate;
      case 'administrator':
        return RichfieldRole.admin;
      default:
        return RichfieldRole.student;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: authService.fetchOwnProfile(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const Scaffold(body: Center(child: Text('Could not load your profile.')));
        }
        final role = _roleFromProfile(snapshot.data!['role'] as String?);
        return RootShell(role: role, authService: authService);
      },
    );
  }
}

// --- Placeholders: swap these for Kesh's actual screen widgets. ---
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text(label)));
}

class MfaSetupScreenPlaceholder extends _PlaceholderScreen {
  const MfaSetupScreenPlaceholder() : super('Set up MFA');
}

class PendingApprovalScreenPlaceholder extends _PlaceholderScreen {
  const PendingApprovalScreenPlaceholder() : super('Pending approval');
}

class AccountRejectedScreenPlaceholder extends _PlaceholderScreen {
  const AccountRejectedScreenPlaceholder() : super('Account rejected');
}

class AdminHomeScreenPlaceholder extends _PlaceholderScreen {
  const AdminHomeScreenPlaceholder() : super('Admin');
}

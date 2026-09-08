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
        // needs an actual fetch. Cache it in your app's auth state
        // provider rather than querying on every navigation — this is
        // simplified for clarity.
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
        } on PostgrestException {
          // RLS denied the profile read or it doesn't exist yet — treat as
          // not-yet-provisioned rather than crashing the redirect.
          return '/login';
        }
      }

      return null; // no redirect needed
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreenPlaceholder()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupScreenPlaceholder()),
      GoRoute(path: '/mfa-setup', builder: (context, state) => const MfaSetupScreenPlaceholder()),
      GoRoute(path: '/pending-approval', builder: (context, state) => const PendingApprovalScreenPlaceholder()),
      GoRoute(path: '/account-rejected', builder: (context, state) => const AccountRejectedScreenPlaceholder()),
      GoRoute(path: '/home', builder: (context, state) => const HomeScreenPlaceholder()),
      GoRoute(path: '/admin', builder: (context, state) => const AdminHomeScreenPlaceholder()),
      GoRoute(path: '/', redirect: (context, state) => '/home'),
    ],
  );
}

// --- Placeholders: swap these for Kesh's actual screen widgets. ---
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text(label)));
}

class LoginScreenPlaceholder extends _PlaceholderScreen {
  const LoginScreenPlaceholder() : super('Login');
}

class SignupScreenPlaceholder extends _PlaceholderScreen {
  const SignupScreenPlaceholder() : super('Sign up');
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

class HomeScreenPlaceholder extends _PlaceholderScreen {
  const HomeScreenPlaceholder() : super('Home');
}

class AdminHomeScreenPlaceholder extends _PlaceholderScreen {
  const AdminHomeScreenPlaceholder() : super('Admin');
}

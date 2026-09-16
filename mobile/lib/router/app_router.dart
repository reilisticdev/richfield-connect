// mobile/lib/router/app_router.dart
//
// GoRouter wired to Supabase's actual auth state, not a placeholder bool.
// Route guards read currentSession + (when needed) the profile's role and
// account_status, so redirects match what the database will actually allow.

import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_error_mapper.dart';
import '../services/auth_service.dart';
import '../services/email_confirmation.dart';
import '../services/media_service.dart';
import '../screens/reset_password_screen.dart';
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
    // onError too: supabase_flutter reports a failed deep-link code exchange
    // (link opened on the wrong device, code already used) as a stream
    // error. Without a handler that was an unhandled exception; with one
    // the router simply re-evaluates and stays on /login.
    _subscription = stream
        .asBroadcastStream()
        .listen((_) => notifyListeners(), onError: (_) => notifyListeners());
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

      // No session: auth pages are fine, everything else goes to login.
      if (!loggedIn) {
        return isGoingToAuth ? null : '/login';
      }

      // Signed in from a password-reset link/code: finish that first.
      if (authService.recoveryPending && state.matchedLocation != '/reset-password') {
        return '/reset-password';
      }

      // A session that exists on the phone can already be dead on the
      // server: an administrator removed the account (auth user and profile
      // row gone), or suspended it (GoTrue revoked the sessions; the access
      // token keeps working only until it expires). That has to be resolved
      // BEFORE the "logged in on an auth page -> /home" bounce below. With
      // the order the other way round the app looped:
      //   /home -> no profile row -> /login -> has a session -> /home -> ...
      // until GoRouter threw "redirect loop detected" (Keshav, testing
      // admin remove, 2026-09-12).
      //
      // account_status / role live in `profiles`, not the JWT, so this is a
      // real fetch; AuthService.fetchOwnProfile() caches it for a short TTL.
      Map<String, dynamic>? profile;
      try {
        profile = await authService.fetchOwnProfile();
      } on PostgrestException catch (e) {
        if (_sessionIsDead(e)) {
          // Drop the dead token on this device (a server-side sign-out
          // would fail: the user is gone or banned). The refresh stream
          // then re-runs this redirect with no session, and /login is a
          // stable stop instead of a bounce.
          await authService.signOutLocally();
          return _toLogin(state, reason: e.code == 'PGRST116' ? 'removed' : 'signed-out');
        }
        // Any other Postgrest error (transient 5xx, a momentary RLS or
        // connection hiccup) must NOT force a logout mid-session.
      } on AuthException catch (_) {
        // The token was refused outright: expired and the refresh failed,
        // which is what a ban looks like once the old token runs out.
        await authService.signOutLocally();
        return _toLogin(state, reason: 'signed-out');
      } catch (_) {
        // Non-Postgrest failure (e.g. a dropped connection). Same
        // reasoning — don't force a logout over a transient error.
      }

      // Live session sitting on an auth page -> into the app.
      if (isGoingToAuth) {
        return '/home';
      }

      // Profile-level gates a session alone can't tell you (pending
      // approval, suspension, admin-only routes). A null profile here means
      // a transient fetch failure; stay on the current route.
      if (profile != null) {
        final accountStatus = profile['account_status'] as String?;
        final role = profile['role'] as String?;

        if (accountStatus == 'pending' && state.matchedLocation != '/pending-approval') {
          return '/pending-approval';
        }
        if (accountStatus == 'rejected' && state.matchedLocation != '/account-rejected') {
          return '/account-rejected';
        }
        // Migration 033 also bans a suspended account, so this only covers
        // the minutes until the current access token expires; after that
        // the AuthException branch above signs the device out.
        if (accountStatus == 'suspended' && state.matchedLocation != '/account-suspended') {
          return '/account-suspended';
        }
        if (state.matchedLocation.startsWith('/admin') && role != 'administrator') {
          return '/home'; // not an admin — bounce, don't 403 silently
        }
      }

      return null; // no redirect needed
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginScreen(
          authService: authService,
          notice: _loginNotice(state.uri.queryParameters['reason']),
        ),
      ),
      GoRoute(path: '/signup', builder: (context, state) => RegisterScreen(authService: authService)),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => ResetPasswordScreen(authService: authService),
      ),
      GoRoute(
        path: '/pending-approval',
        builder: (context, state) => AccountStatusScreen(authService: authService, status: 'pending'),
      ),
      GoRoute(
        path: '/account-rejected',
        builder: (context, state) => AccountStatusScreen(authService: authService, status: 'rejected'),
      ),
      GoRoute(
        path: '/account-suspended',
        builder: (context, state) => AccountStatusScreen(authService: authService, status: 'suspended'),
      ),
      GoRoute(path: '/home', builder: (context, state) => _HomeGate(authService: authService)),
      GoRoute(path: '/admin', builder: (context, state) => const AdminHomeScreenPlaceholder()),
      GoRoute(path: '/', redirect: (context, state) => '/home'),
    ],
  );
}

/// PGRST116: `.single()` found no row — the profile is gone. A signed-in
/// user with no profile row can only mean the account was removed
/// (handle_new_user() creates the row in the same transaction as the auth
/// user). PGRST301/302/303: PostgREST refused the JWT itself.
bool _sessionIsDead(PostgrestException e) =>
    e.code == 'PGRST116' || e.code == 'PGRST301' || e.code == 'PGRST302' || e.code == 'PGRST303';

/// Route to /login with a reason the screen can explain. Returning null
/// when already on /login is what ends the redirect chain.
String? _toLogin(GoRouterState state, {required String reason}) {
  if (state.matchedLocation == '/login') return null;
  return '/login?reason=$reason';
}

String? _loginNotice(String? reason) => switch (reason) {
      'removed' => 'This account is no longer active. Sign in with another account or register a new one.',
      'signed-out' => 'Your session has ended. Please sign in again.',
      _ => null,
    };

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

/// Where a signed-in account that isn't active lands: waiting for approval,
/// not approved, or suspended by an administrator. Each explains the state
/// and offers Sign out, so nobody is stuck on a blank screen.
class AccountStatusScreen extends StatelessWidget {
  const AccountStatusScreen({super.key, required this.authService, required this.status});

  final AuthService authService;

  /// profiles.account_status: 'pending', 'rejected' or 'suspended'.
  final String status;

  String get _title => switch (status) {
        'rejected' => 'Account not approved',
        'suspended' => 'Account suspended',
        _ => 'Waiting for approval',
      };

  IconData get _icon => switch (status) {
        'rejected' => Icons.block_outlined,
        'suspended' => Icons.pause_circle_outline,
        _ => Icons.hourglass_top_outlined,
      };

  String _message(String? role) {
    if (status == 'rejected') {
      return 'A Richfield administrator reviewed this account and did not approve it.';
    }
    if (status == 'suspended') {
      return 'A Richfield administrator has suspended this account, so you can\'t use Richfield Connect '
          'for now. Contact Richfield if you think this is a mistake.';
    }
    switch (role) {
      case 'alumni':
        return 'A Richfield administrator is checking your student number and graduation details. '
            'You can use Richfield Connect once your account is approved.';
      case 'business':
        return 'A Richfield administrator is reviewing your company. '
            'You can post opportunities once your account is approved.';
      default:
        return 'Your account is waiting for a Richfield administrator to approve it.';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (status == 'pending') {
      // A brand-new alumni/business account arriving straight from the
      // confirmation code or link: say the email part worked before
      // explaining the wait. One-shot; a no-op on every later build.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => EmailConfirmation.showWelcomeIfDue(context, awaitingApproval: true),
      );
    }

    final waiting = status == 'pending';
    return Scaffold(
      backgroundColor: AppColors.surfaceContainerLow,
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: authService.fetchOwnProfile(),
          builder: (context, snapshot) {
            final role = snapshot.data?['role'] as String?;
            return Padding(
              padding: EdgeInsets.all(AppSpace.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(_icon, size: 56, color: waiting ? AppColors.primary : AppColors.error),
                  SizedBox(height: AppSpace.md),
                  Text(
                    _title,
                    textAlign: TextAlign.center,
                    style: AppText.headlineLg(),
                  ),
                  SizedBox(height: AppSpace.sm),
                  Text(
                    _message(role),
                    textAlign: TextAlign.center,
                    style: AppText.bodyMd(color: AppColors.onSurfaceVariant),
                  ),
                  if (waiting && role == 'business') ...[
                    SizedBox(height: AppSpace.lg),
                    _BusinessDocumentUpload(authService: authService),
                  ],
                  SizedBox(height: AppSpace.xl),
                  // signOut() fires onAuthStateChange, and the redirect above
                  // sends a signed-out user to /login.
                  OutlinedButton.icon(
                    onPressed: authService.signOut,
                    icon: Icon(Icons.logout),
                    label: Text('Sign out'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Registration number already travelled in at signup (migration 045); the
/// supporting document couldn't - there's no session yet at signUp() time,
/// with email confirmation on. This is that upload step, offered the one
/// place a pending business account is guaranteed to land.
class _BusinessDocumentUpload extends StatefulWidget {
  const _BusinessDocumentUpload({required this.authService});

  final AuthService authService;

  @override
  State<_BusinessDocumentUpload> createState() => _BusinessDocumentUploadState();
}

class _BusinessDocumentUploadState extends State<_BusinessDocumentUpload> {
  static const _docTypes = XTypeGroup(
    label: 'Document',
    extensions: ['pdf', 'jpg', 'jpeg', 'png'],
    mimeTypes: ['application/pdf', 'image/jpeg', 'image/png'],
    uniformTypeIdentifiers: ['com.adobe.pdf', 'public.jpeg', 'public.png'],
  );

  final _media = MediaService(Supabase.instance.client);
  bool _busy = false;
  bool _uploaded = false;
  String? _error;

  Future<void> _pickAndUpload() async {
    final userId = widget.authService.currentUser?.id;
    if (userId == null) return;

    final XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: const [_docTypes]);
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn\'t open a file picker on this device.');
      return;
    }
    if (file == null || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Uint8List bytes = await file.readAsBytes();
      final extension = '.${file.name.split('.').last.toLowerCase()}';
      final contentType = switch (extension) {
        '.pdf' => 'application/pdf',
        '.png' => 'image/png',
        _ => 'image/jpeg',
      };
      final path = await _media.uploadVerificationDocument(
        bucket: MediaService.businessVerificationDocsBucket,
        userId: userId,
        bytes: bytes,
        extension: extension,
        contentType: contentType,
      );
      await Supabase.instance.client
          .from('business_profiles')
          .update({'document_path': path})
          .eq('profile_id', userId);
      if (mounted) setState(() => _uploaded = true);
    } catch (e) {
      if (mounted) setState(() => _error = AuthErrorMapper.fromAny(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Upload your company registration document (PDF or photo) so an '
          'administrator can verify it alongside your registration number.',
          textAlign: TextAlign.center,
          style: AppText.bodySm(color: AppColors.onSurfaceVariant),
        ),
        SizedBox(height: AppSpace.sm),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickAndUpload,
          icon: _busy
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(_uploaded ? Icons.check_circle_outline : Icons.upload_file_outlined),
          label: Text(_uploaded ? 'Document uploaded — tap to replace' : 'Upload registration document'),
        ),
        if (_error != null) ...[
          SizedBox(height: AppSpace.xs),
          Text(_error!, textAlign: TextAlign.center, style: AppText.bodySm(color: AppColors.error)),
        ],
      ],
    );
  }
}

class AdminHomeScreenPlaceholder extends _PlaceholderScreen {
  const AdminHomeScreenPlaceholder() : super('Admin');
}

// =====================================================================
// RICHFIELD GRADUATE NETWORK — Flutter UI Prototype
// -----------------------------------------------------------------------
// Converted from the Google Stitch HTML/Tailwind export (DESIGN.md +
// code.html) for the 2026 Richfield Hackathon brief.
//
// SCOPE OF THIS FILE (read this before extending it):
//   - UPDATE (mobile integration pass): LoginScreen, RegisterScreen, and
//     sign-out on PortfolioScreen now call the real AuthService
//     (../services/auth_service.dart) against a real Supabase project
//     (see config/supabase_config.dart), and navigation runs through
//     go_router (../router/app_router.dart) instead of manual Navigator
//     calls — see _HomeGate in app_router.dart for how the post-login role
//     (Feed vs BusinessHub vs AdminHub) gets resolved from `profiles`.
//   - Every tab now reads real tables. The MockData class that used to feed
//     the Feed, Jobs, Network and Portfolio content and the dashboards is
//     gone; an empty section means the database has no rows for it yet.
//   - Two screens (Jobs, Network) had no corresponding Stitch export, so
//     they were built to match the existing design system rather than
//     left blank — swap them for your real designs when ready.
//
// Performance note: built with A14-class phones (iPhone 12 family /
// iPhone SE 3rd gen / iPad Air 4) in mind — no heavyweight image
// decoding, no unnecessary rebuilds, `const` constructors used wherever
// the widget tree allows it.
// =====================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config/supabase_config.dart';
import 'screens/edit_profile_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/privacy_settings_screen.dart';
import 'services/auth_error_mapper.dart';
import 'services/auth_service.dart';
import 'services/jobs_service.dart';
import 'services/media_service.dart';
import 'services/profile_service.dart';
import 'services/business_analytics_service.dart';
import 'services/feed_service.dart';
// app_router.dart imports this file back for the real screen widgets
// (LoginScreen, RegisterScreen, RootShell) — a legal, ordinary circular
// import in Dart, not a mistake.
import 'router/app_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/push_notification_service.dart';
import 'config/ai_config.dart';
import 'screens/ai_assistant_screen.dart';
import 'screens/cv_import_screen.dart';
import 'screens/career_pathways_screen.dart';
import 'screens/events_screen.dart';
import 'services/profile_context_service.dart';
import 'screens/messages_screen.dart';
import 'screens/network_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/comments_sheet.dart';
import 'widgets/report_content_dialog.dart';
import 'services/notifications_service.dart';
import 'services/realtime_hub.dart';
import 'services/portfolio_service.dart';
import 'services/student_analytics_service.dart';
import 'services/admin_analytics_service.dart';
import 'services/connections_service.dart' show PersonSummary;
import 'screens/portfolio_entry_sheet.dart';
import 'widgets/profile_avatar.dart';
import 'widgets/time_labels.dart' show eventDateLabel, monthYearLabel;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Deliberately NOT awaited. initialize() calls requestPermission(), which
  // puts up the system notification dialog and doesn't return until the user
  // answers it. Awaiting that here blocks runApp() — verified on an emulator
  // 2026-09-11: the app rendered nothing but a grey screen behind the dialog
  // for a full 60 seconds until Allow was tapped, and the FCM token only
  // arrived afterwards. Letting it run in the background means the login
  // screen paints immediately and the permission prompt appears over it.
  unawaited(PushNotificationService.initialize());

  await ThemeController.loadSaved();
  await AiConfig.load();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );
  final authService = AuthService(Supabase.instance.client);

  // Writes the device's FCM token onto whichever profile is signed in.
  // Has to happen here, not inside PushNotificationService.initialize()
  // above — that runs before Supabase.initialize() and before any user is
  // signed in, so there's no profile row yet to write to. Covers both a
  // fresh sign-in (the stream fires) and reopening the app with an
  // existing session (the explicit call right after covers the case
  // where the stream's initial emission is missed by subscribing late).
  Supabase.instance.client.auth.onAuthStateChange.listen((_) {
    unawaited(PushNotificationService.syncTokenIfSignedIn());
  });
  unawaited(PushNotificationService.syncTokenIfSignedIn());

  runApp(RichfieldConnectApp(authService: authService));
}

class ThemeController {
  ThemeController._();

  static final ValueNotifier<bool> isDarkNotifier = ValueNotifier<bool>(false);
  static const _prefsKey = 'richfield_dark_mode';

  static bool get isDark => isDarkNotifier.value;

  static Future<void> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    isDarkNotifier.value = prefs.getBool(_prefsKey) ?? false;
  }

  static Future<void> toggle() => setDark(!isDark);

  static Future<void> setDark(bool value) async {
    isDarkNotifier.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }
}

class RichfieldLogo extends StatelessWidget {
  final double size;

  RichfieldLogo({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'richfield-spinner-animated.svg',
      width: size,
      height: size,
      semanticsLabel: 'Richfield logo',
    );
  }
}

// =====================================================================
// SECTION 1 — DESIGN SYSTEM (colors, type scale, spacing, radii)
// Pulled 1:1 from DESIGN.md's YAML token block / code.html's Tailwind
// config, which is the *implemented* palette (not the aspirational
// "Crimson / Navy / Gold" palette described in DESIGN.md's prose — see
// the chat feedback on that mismatch).
// =====================================================================

class AppColors {
  AppColors._();

  static bool get _dark => ThemeController.isDark;
  static Color get surface => _dark ? Color(0xFF090D16) : Color(0xFFFAF8FF);
  static Color get surfaceContainerLowest =>
    _dark ? Color(0xFF111827) : Color(0xFFFFFFFF);
  static Color get surfaceContainerLow =>
    _dark ? Color(0xFF0D1320) : Color(0xFFF2F3FF);
  static Color get surfaceContainer =>
    _dark ? Color(0xFF141C2C) : Color(0xFFEAEDFF);
  static Color get surfaceContainerHigh =>
    _dark ? Color(0xFF1B2436) : Color(0xFFE2E7FF);
  static Color get surfaceContainerHighest =>
    _dark ? Color(0xFF1E293B) : Color(0xFFDAE2FD);
  static Color get onSurface => _dark ? Color(0xFFF8FAFC) : Color(0xFF131B2E);
  static Color get onSurfaceVariant =>
    _dark ? Color(0xFF94A3B8) : Color(0xFF5C403F);
  static Color get inverseSurface =>
    _dark ? Color(0xFFF8FAFC) : Color(0xFF283044);
  static Color get inverseOnSurface =>
    _dark ? Color(0xFF131B2E) : Color(0xFFEEF0FF);
  static Color get outline => _dark ? Color(0xFF475569) : Color(0xFF906F6E);
  static Color get outlineVariant =>
    _dark ? Color(0xFF1E293B) : Color(0xFFE4BDBC);
  static Color get surfaceTint => _dark ? Color(0xFF6E93D1) : Color(0xFFBD092B);
  static Color get primary => _dark ? Color(0xFF6E93D1) : Color(0xFF9A0020);
  static Color get onPrimary => _dark ? Color(0xFF0B1B33) : Colors.white;
  static Color get primaryContainer =>
    _dark ? Color(0xFF0F2C59) : Color(0xFFC4122F);
  static Color get onPrimaryContainer =>
    _dark ? Color(0xFFD8E2FF) : Color(0xFFFFD6D4);
  static Color get secondary => _dark ? Color(0xFF9DB8E8) : Color(0xFF465E8E);
  static Color get onSecondary => _dark ? Color(0xFF12233F) : Colors.white;
  static Color get secondaryContainer =>
    _dark ? Color(0xFF2D4674) : Color(0xFFB1C9FF);
  static Color get onSecondaryContainer =>
    _dark ? Color(0xFFD8E2FF) : Color(0xFF3B5483);
  static Color get tertiary => _dark ? Color(0xFFE9C349) : Color(0xFF735C00);
  static Color get onTertiary => _dark ? Color(0xFF3F3000) : Colors.white;
  static Color get tertiaryContainer =>
    _dark ? Color(0xFF574500) : Color(0xFFCBA72F);
  static Color get onTertiaryContainer =>
    _dark ? Color(0xFFFFE088) : Color(0xFF4E3D00);
  static const tertiaryFixed = Color(0xFFFFE088);
  static const tertiaryFixedDim = Color(0xFFE9C349);
  static Color get error => _dark ? Color(0xFFFFB4AB) : Color(0xFFBA1A1A);
  static Color get onError => _dark ? Color(0xFF690005) : Colors.white;
  static Color get errorContainer =>
    _dark ? Color(0xFF93000A) : Color(0xFFFFDAD6);
  static Color get onErrorContainer =>
    _dark ? Color(0xFFFFDAD6) : Color(0xFF93000A);
  static Color get background => surface;
  static Color get onBackground => onSurface;
  static Color get surfaceVariant => surfaceContainerHighest;
  static Color get successGreen => _dark ? Color(0xFF10B981) : Color(0xFF059669);
  static Color get successGreenBg =>
    _dark ? Color(0xFF0F2A20) : Color(0xFFECFDF5);
}

class AppRadius {
  AppRadius._();
  static const sm = 2.0;
  static const md = 6.0;
  static const lg = 8.0;
  static const xl = 12.0;
  static const full = 999.0;
}

class AppSpace {
  AppSpace._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const base = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// Central place for the DESIGN.md Inter type scale. Using a helper
/// instead of a static TextTheme keeps call sites terse: `AppText.bodyMd()`.
class AppText {
  AppText._();

  static TextStyle _s(
    double size,
    FontWeight weight,
    double lineHeight,
    double letterSpacing, {
    Color? color,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      height: lineHeight / size,
      letterSpacing: letterSpacing,
      color: color ?? AppColors.onSurface,
    );
  }

  static TextStyle displayLg({Color? color}) =>
      _s(36, FontWeight.w800, 44, -0.9, color: color);
  static TextStyle displayLgMobile({Color? color}) =>
      _s(28, FontWeight.w800, 34, -0.56, color: color);
  static TextStyle headlineLg({Color? color}) =>
      _s(24, FontWeight.w700, 32, -0.36, color: color);
  static TextStyle headlineMd({Color? color}) =>
      _s(20, FontWeight.w600, 28, -0.2, color: color);
  static TextStyle headlineSm({Color? color}) =>
      _s(18, FontWeight.w600, 24, -0.09, color: color);
  static TextStyle bodyLg({Color? color}) =>
      _s(16, FontWeight.w400, 24, 0, color: color);
  static TextStyle bodyMd({Color? color}) =>
      _s(14, FontWeight.w400, 20, 0, color: color);
  static TextStyle bodySm({Color? color}) =>
      _s(12, FontWeight.w400, 16, 0.12, color: color);
  static TextStyle labelLg({Color? color}) =>
      _s(14, FontWeight.w600, 18, 0.14, color: color);
  static TextStyle labelMd({Color? color}) =>
      _s(12, FontWeight.w600, 16, 0.24, color: color);
  static TextStyle labelBadge({Color? color}) =>
      _s(10, FontWeight.w700, 12, 0.5, color: color);
}

// =====================================================================
// SECTION 2 — APP ROOT
// =====================================================================

/// NOTE (theme repair): this used to be a StatelessWidget whose build ran
/// `routerConfig: buildAppRouter(authService)` INSIDE the
/// ValueListenableBuilder. Because that call sits in the builder, every
/// single dark-mode toggle constructed a brand-new GoRouter, which:
///
///   1. reset the navigation stack to initialLocation ('/') — so toggling
///      the theme anywhere in the app threw the user back to the feed root
///      and closed whatever screen they were on;
///   2. built a new GoRouterRefreshStream each time, each one opening
///      another subscription to authService.onAuthStateChange that was
///      never disposed — a listener leak that grows with every toggle.
///
/// The router is now created exactly once and held in State. The theme
/// still rebuilds MaterialApp (colours are re-read from AppColors on every
/// build), but navigation and the auth subscription survive the toggle.
class RichfieldConnectApp extends StatefulWidget {
  const RichfieldConnectApp({super.key, required this.authService});

  final AuthService authService;

  @override
  State<RichfieldConnectApp> createState() => _RichfieldConnectAppState();
}

class _RichfieldConnectAppState extends State<RichfieldConnectApp> {
  late final _router = buildAppRouter(widget.authService);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.isDarkNotifier,
      builder: (context, isDark, _) {
        final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.onPrimaryContainer,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onSecondary,
      secondaryContainer: AppColors.secondaryContainer,
      onSecondaryContainer: AppColors.onSecondaryContainer,
      tertiary: AppColors.tertiary,
      onTertiary: AppColors.onTertiary,
      tertiaryContainer: AppColors.tertiaryContainer,
      onTertiaryContainer: AppColors.onTertiaryContainer,
      error: AppColors.error,
      onError: AppColors.onError,
      errorContainer: AppColors.errorContainer,
      onErrorContainer: AppColors.onErrorContainer,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineVariant,
      // Theme repair: these roles were never registered, so ColorScheme
      // .fromSeed() derived them from the seed instead of using the app's
      // own palette. Every Material surface that resolves its own
      // container colour — Card, Dialog, BottomSheet (the account menu),
      // SnackBar, PopupMenu, NavigationBar — therefore painted a seeded
      // tint that did not match the hand-built AppColors panels next to
      // it. Most visible in dark mode, where the seeded container came out
      // washed-out purple against the navy #0D1320 the rest of the app uses.
      onSurfaceVariant: AppColors.onSurfaceVariant,
      surfaceContainerLowest: AppColors.surfaceContainerLowest,
      surfaceContainerLow: AppColors.surfaceContainerLow,
      surfaceContainer: AppColors.surfaceContainer,
      surfaceContainerHigh: AppColors.surfaceContainerHigh,
      surfaceContainerHighest: AppColors.surfaceContainerHighest,
      inverseSurface: AppColors.inverseSurface,
      onInverseSurface: AppColors.inverseOnSurface,
      surfaceTint: AppColors.surfaceTint,
      );

      return MaterialApp.router(
      title: 'Richfield Graduate Network',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: isDark ? Brightness.dark : Brightness.light,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: AppColors.surface,
        fontFamily: GoogleFonts.inter().fontFamily,
        splashFactory: InkRipple.splashFactory,
      ),
          routerConfig: _router,
        );
      },
    );
  }
}

// =====================================================================
// SECTION 3 — MOCK DATA MODELS + SAMPLE DATA
// Everything here stands in for real API/database responses. Swap this
// section out first when you connect a real backend.
// =====================================================================

enum RichfieldRole { student, alumni, corporate, admin }

extension RichfieldRoleX on RichfieldRole {
  String get label {
    switch (this) {
      case RichfieldRole.student:
        return 'Student';
      case RichfieldRole.alumni:
        return 'Alumni';
      case RichfieldRole.corporate:
        return 'Corporate';
      case RichfieldRole.admin:
        return 'Staff / Admin';
    }
  }

  String get sublabel {
    switch (this) {
      case RichfieldRole.student:
        return '@my.richfield.ac.za';
      case RichfieldRole.alumni:
        return 'Richfield graduate';
      case RichfieldRole.corporate:
        return 'Partner Recruiter';
      case RichfieldRole.admin:
        return 'Richfield staff';
    }
  }

  IconData get icon {
    switch (this) {
      case RichfieldRole.student:
        return Icons.school_outlined;
      case RichfieldRole.alumni:
        return Icons.workspace_premium_outlined;
      case RichfieldRole.corporate:
        return Icons.apartment_outlined;
      case RichfieldRole.admin:
        return Icons.admin_panel_settings_outlined;
    }
  }
}

enum FeedPostType { text, video }

class FeedPost {
  /// Database id.
  final String? id;

  /// posts.author_id, so a card can hide Report on the viewer's own post.
  final String? authorId;

  /// Public CDN url for an image post (posts.image_path resolved through
  /// the post-media bucket). Null for text-only and video posts.
  final String? imageUrl;

  /// Whether the signed-in user has already reposted this.
  final bool isReposted;

  /// Whether the signed-in user has already liked this.
  final bool isReacted;

  final FeedPostType type;
  final String authorName;
  final String authorRole;
  final bool verified;
  final String timeAgo;
  final String body;
  final String? videoLabel;

  /// Reactions, comments and reposts, from the aggregate embeds in
  /// FeedService.postFields.
  final int reactionCountA;
  final int reactionCountB;
  final int reactionCountC;

  FeedPost({
    this.id,
    this.authorId,
    this.imageUrl,
    this.isReposted = false,
    this.isReacted = false,
    required this.type,
    required this.authorName,
    required this.authorRole,
    required this.verified,
    required this.timeAgo,
    required this.body,
    this.videoLabel,
    required this.reactionCountA,
    required this.reactionCountB,
    required this.reactionCountC,
  });

  /// Cheap immutable update so the feed can flip one card's like, comment or
  /// repost state without re-querying the whole list.
  FeedPost copyWith({
    bool? isReposted,
    bool? isReacted,
    int? reactionCountA,
    int? reactionCountB,
    int? reactionCountC,
  }) {
    return FeedPost(
      id: id,
      authorId: authorId,
      imageUrl: imageUrl,
      isReposted: isReposted ?? this.isReposted,
      isReacted: isReacted ?? this.isReacted,
      type: type,
      authorName: authorName,
      authorRole: authorRole,
      verified: verified,
      timeAgo: timeAgo,
      body: body,
      videoLabel: videoLabel,
      reactionCountA: reactionCountA ?? this.reactionCountA,
      reactionCountB: reactionCountB ?? this.reactionCountB,
      reactionCountC: reactionCountC ?? this.reactionCountC,
    );
  }
}

// Maps a real `posts` row (joined to `profiles` for the author) onto the
// FeedPost UI model shared by the Feed and Portfolio cards.
FeedPost _feedPostFromRow(
  Map<String, dynamic> row, {
  Set<String> repostedIds = const <String>{},
  Set<String> reactedIds = const <String>{},
  MediaService? mediaService,
}) {
  final profile = row['profiles'] as Map<String, dynamic>?;
  final id = row['id'] as String?;
  final imagePath = row['image_path'] as String?;
  final name = ('${profile?['first_name'] ?? ''} ${profile?['last_name'] ?? ''}').trim();
  final role = profile?['role'] as String?;
  final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now();
  return FeedPost(
    id: id,
    authorId: row['author_id'] as String?,
    imageUrl: (imagePath != null && imagePath.isNotEmpty && mediaService != null)
        ? mediaService.postImageUrl(imagePath)
        : null,
    isReposted: id != null && repostedIds.contains(id),
    isReacted: id != null && reactedIds.contains(id),
    type: row['video_path'] != null ? FeedPostType.video : FeedPostType.text,
    authorName: name.isEmpty ? 'Richfield Member' : name,
    authorRole: role == null || role.isEmpty ? '' : role[0].toUpperCase() + role.substring(1),
    verified: true,
    timeAgo: _timeAgo(createdAt),
    body: row['body'] as String? ?? '',
    videoLabel: row['video_path'] != null ? 'Video post' : null,
    reactionCountA: _embeddedCount(row['reactions']),
    reactionCountB: _embeddedCount(row['comments']),
    reactionCountC: _embeddedCount(row['post_reposts']),
  );
}

/// A PostgREST aggregate embed such as `post_reposts(count)` comes back as
/// [{'count': n}], or an empty list when nothing references the row.
int _embeddedCount(Object? embed) {
  if (embed is List && embed.isNotEmpty) {
    final first = embed.first;
    if (first is Map && first['count'] is int) return first['count'] as int;
  }
  return 0;
}

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

// =====================================================================
// SECTION 4 — SHARED SMALL WIDGETS
// =====================================================================

/// Small rounded pill used for verification badges, status tags, and
/// filter chips throughout the app — mirrors the Stitch "chip" component.
class Pill extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;
  final IconData? icon;
  final double fontSize;

  Pill({
    super.key,
    required this.text,
    required this.background,
    required this.foreground,
    this.icon,
    this.fontSize = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 4, color: foreground),
            SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: AppText.labelBadge(color: foreground).copyWith(fontSize: fontSize),
            ),
          ),
        ],
      ),
    );
  }
}

class PrimaryButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool fullWidth;

  PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.fullWidth = true,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _glow = false;

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton(
      onPressed: widget.onPressed == null
          ? null
          : () {
              setState(() => _glow = true);
              Future<void>.delayed(Duration(milliseconds: 260), () {
                if (mounted) setState(() => _glow = false);
              });
              widget.onPressed!();
            },
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        padding: EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        elevation: 0,
        shadowColor: AppColors.primary,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 18),
            SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              widget.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.labelLg(color: AppColors.onPrimary),
            ),
          ),
        ],
      ),
    );
    final wrapped = AnimatedContainer(
      duration: Duration(milliseconds: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: _glow ? [BoxShadow(color: AppColors.primary.withOpacity(.55), blurRadius: 16, spreadRadius: 2)] : null,
      ),
      child: button,
    );
    return widget.fullWidth ? SizedBox(width: double.infinity, child: wrapped) : wrapped;
  }
}

class SecondaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  SecondaryButton({super.key, required this.label, this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.onSurface,
          side: BorderSide(color: AppColors.outlineVariant),
          padding: EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16),
              SizedBox(width: 6),
            ],
            Text(label, style: AppText.labelMd()),
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final VoidCallback? onTrailingTap;

  SectionHeader({super.key, required this.title, this.trailing, this.onTrailingTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: AppText.headlineSm()),
          if (trailing != null)
            GestureDetector(
              onTap: onTrailingTap,
              child: Text(
                trailing!,
                style: AppText.labelMd(color: AppColors.secondary),
              ),
            ),
        ],
      ),
    );
  }
}

class RoundedCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Border? border;

  RoundedCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.base),
    this.color,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: border ?? Border.all(color: AppColors.outlineVariant.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withOpacity(0.04),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Circular initials avatar — stands in for a real profile photo so this
/// prototype never depends on network images.
class InitialsAvatar extends StatelessWidget {
  final String initials;
  final double radius;
  final Color background;
  final Color foreground;

  InitialsAvatar({
    super.key,
    required this.initials,
    this.radius = 20,
    Color? background,
    Color? foreground,
  })  : background = background ?? AppColors.secondaryContainer,
        foreground = foreground ?? AppColors.onSecondaryContainer;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: background,
      child: Text(
        initials,
        style: AppText.labelLg(color: foreground).copyWith(fontSize: radius * 0.7),
      ),
    );
  }
}

/// Shared top header (logo mark + title/subtitle + bell + avatar) used by
/// every tab inside the RootShell, matching the Feed/Portfolio screenshots.
class RichfieldHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onAvatarTap;
  final Widget? extraAction;

  RichfieldHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.onAvatarTap,
    this.extraAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.base, AppSpace.sm, AppSpace.base, AppSpace.sm),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: RichfieldLogo(size: 26),
          ),
          SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.headlineMd()),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: AppColors.successGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.labelBadge(color: AppColors.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (extraAction != null) extraAction!,
          ValueListenableBuilder<bool>(
            valueListenable: ThemeController.isDarkNotifier,
            builder: (context, isDark, _) => IconButton(
              tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
              onPressed: ThemeController.toggle,
              icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
              color: AppColors.primary,
            ),
          ),
          // Was IconButton(onPressed: () {}) — a bell that did nothing. The
          // badge is RealtimeHub's unread count, updated over the WebSocket.
          ValueListenableBuilder<int>(
            valueListenable: RealtimeHub.instance.unreadNotifications,
            builder: (context, unread, _) => IconButton(
              tooltip: 'Notifications',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => NotificationsScreen()),
              ),
              icon: Badge(
                isLabelVisible: unread > 0,
                label: Text(unread > 99 ? '99+' : '$unread'),
                child: Icon(Icons.notifications_none_rounded),
              ),
              color: AppColors.onSurface,
            ),
          ),
          GestureDetector(
            onTap: onAvatarTap,
            child: CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primary,
              child: Icon(Icons.person, size: 18, color: AppColors.onPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

// Shared account-menu bottom sheet (Onboarding Tour / Log Out). Top-level so
// every tab's RichfieldHeader.onAvatarTap can call it, not just Portfolio's.
void _openAccountMenu(BuildContext context, AuthService authService) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surfaceContainerLowest,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.help_outline),
            title: Text('Take the Onboarding Tour'),
            onTap: () {
              Navigator.pop(context);
              _startOnboardingTour(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.route_outlined),
            title: Text('Career pathways'),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CareerPathwaysScreen()),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.event_outlined),
            title: Text('Events'),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => EventsScreen()),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.auto_awesome_outlined),
            title: Text('Career AI assistant'),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AiAssistantScreen()),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('Privacy & data'),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PrivacySettingsScreen()),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.logout, color: AppColors.error),
            title: Text('Log Out', style: TextStyle(color: AppColors.error)),
            onTap: () async {
              Navigator.pop(context);
              await authService.signOut();
              // go_router's redirect (listening to onAuthStateChange)
              // bounces to /login on its own — no manual navigation here.
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _startOnboardingTour(BuildContext context) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      pageBuilder: (_, __, ___) => OnboardingTourOverlay(),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ),
  );
}

// =====================================================================
// SECTION 5 — AUTH: LOGIN SCREEN
// =====================================================================

class LoginScreen extends StatefulWidget {
  LoginScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  RichfieldRole _selectedRole = RichfieldRole.student;
  bool _obscure = true;
  bool _submitting = false;
  String? _errorMessage;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Role tiles above are cosmetic (hint text/labels only) — signIn takes
  // just email/password; the real role comes back from the profiles row
  // after auth, and app_router.dart's redirect + _HomeGate route the user
  // from there. No manual navigation here on purpose.
  Future<void> _signIn() async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await widget.authService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } catch (e) {
      setState(() => _errorMessage = AuthErrorMapper.fromAny(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceContainerLow,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(AppSpace.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // A "Richfield Secure Vault Initialising… / 256-Bit Hardware
              // Handshake / VAULT ONLINE" banner sat here. It was decoration:
              // sign-in is Supabase email and password over HTTPS.
              SizedBox(height: AppSpace.lg),
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12),
                    ],
                  ),
                  child: RichfieldLogo(size: 60),
                ),
              ),
              SizedBox(height: AppSpace.md),
              Text(
                'Richfield Graduate Network',
                textAlign: TextAlign.center,
                style: AppText.headlineLg(),
              ),
              SizedBox(height: 4),
              Text(
                'RICHFIELD & AAA SCHOOL OF ADVERTISING CAREER NETWORK',
                textAlign: TextAlign.center,
                style: AppText.labelBadge(color: AppColors.secondary),
              ),
              SizedBox(height: AppSpace.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Pill(
                    text: 'CHE & SAQA Accredited',
                    background: AppColors.tertiaryContainer.withOpacity(0.3),
                    foreground: AppColors.tertiary,
                    icon: Icons.school_outlined,
                  ),
                ],
              ),
              SizedBox(height: AppSpace.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Account type', style: AppText.labelLg()),
                  Text('TAP TO SWITCH',
                      style: AppText.labelBadge(color: AppColors.onSurfaceVariant)),
                ],
              ),
              SizedBox(height: AppSpace.sm),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpace.sm,
                crossAxisSpacing: AppSpace.sm,
                childAspectRatio: 2.4,
                children: RichfieldRole.values.map((role) {
                  final selected = role == _selectedRole;
                  return _RoleTile(
                    role: role,
                    selected: selected,
                    onTap: () => setState(() => _selectedRole = role),
                  );
                }).toList(),
              ),
              SizedBox(height: AppSpace.base),
              RoundedCard(
                color: AppColors.secondaryContainer.withOpacity(0.25),
                border: Border.all(color: Colors.transparent),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: AppColors.secondary),
                    SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Student email policy', style: AppText.labelMd()),
                          SizedBox(height: 2),
                          Text(
                            'Student accounts are registered with a Richfield or AAA address: @my.richfield.ac.za, @richfield.ac.za, @my.aaa.ac.za or @aaa.ac.za.',
                            style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // "Continue with Institutional Google" was here, wired to the
              // same email/password _signIn as the form below. Google isn't
              // enabled as a Supabase Auth provider, so it can't be real yet.
              SizedBox(height: AppSpace.base),
                Text(_selectedRole == RichfieldRole.corporate
                  ? 'Work Email'
                  : _selectedRole == RichfieldRole.admin
                    ? 'Administrator Email'
                    : '${_selectedRole.label} Email', style: AppText.labelLg()),
              SizedBox(height: 6),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.alternate_email, size: 18),
                  // The full address is what signs you in. The old hint,
                  // 'student.id' beside a '@my.richfield' pill, suggested the
                  // domain gets filled in for you; it doesn't.
                  hintText: switch (_selectedRole) {
                    RichfieldRole.corporate => 'you@company.co.za',
                    RichfieldRole.admin => 'you@richfield.ac.za',
                    RichfieldRole.alumni => 'you@example.com',
                    RichfieldRole.student => 'you@my.richfield.ac.za',
                  },
                  filled: true,
                  fillColor: AppColors.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              SizedBox(height: AppSpace.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Password', style: AppText.labelLg()),
                  // Was a bare Text() styled to look like a link — no
                  // GestureDetector, no InkWell, no route. Nothing to tap.
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ForgotPasswordScreen(
                          authService: widget.authService,
                          initialEmail: _emailController.text,
                        ),
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text('Forgot?',
                        style: AppText.labelMd(color: AppColors.primary)),
                  ),
                ],
              ),
              SizedBox(height: 6),
              TextField(
                controller: _passwordController,
                obscureText: _obscure,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.lock_outline, size: 18),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        size: 18),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              // A "Trust this device for 30 days via Richfield Mobile Token"
              // checkbox was here, bound to a bool nothing read. Sessions
              // already persist until sign-out.
              SizedBox(height: AppSpace.md),
              if (_errorMessage != null) ...[
                Padding(
                  padding: EdgeInsets.only(bottom: AppSpace.sm),
                  child: Text(_errorMessage!, style: AppText.bodySm(color: AppColors.error)),
                ),
              ],
              SizedBox(height: AppSpace.sm),
              PrimaryButton(
                // The account-type tiles only change the hints; the account's
                // real role comes from its profile after sign-in.
                label: _submitting ? 'SIGNING IN…' : 'SIGN IN',
                icon: Icons.key_outlined,
                onPressed: _submitting ? null : _signIn,
              ),
              SizedBox(height: AppSpace.lg),
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text("Don't have an account yet? ", style: AppText.bodySm()),
                    GestureDetector(
                      onTap: () => context.push('/signup'),
                      child: Text('Register here',
                          style: AppText.bodySm(color: AppColors.primary)
                              .copyWith(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              SizedBox(height: AppSpace.xl),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  final RichfieldRole role;
  final bool selected;
  final VoidCallback onTap;

  _RoleTile({required this.role, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: selected ? Colors.transparent : AppColors.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Icon(role.icon, size: 20, color: selected ? AppColors.onPrimary : AppColors.onSurfaceVariant),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(role.label,
                      style: AppText.labelLg(color: selected ? AppColors.onPrimary : AppColors.onSurface)),
                  Text(role.sublabel,
                      style: AppText.bodySm(
                          color: selected ? AppColors.onPrimary.withOpacity(0.7) : AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: AppColors.onPrimary, size: 18),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// SECTION 6 — AUTH: REGISTER SCREEN
// =====================================================================

class RegisterScreen extends StatefulWidget {
  RegisterScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  int _tab = 0; // 0 = Student, 1 = Alumni, 2 = Employer
  bool _agreed = false;
  bool _submitting = false;
  String? _errorMessage;

  /// Set when signUp succeeds without a session, which is always the case
  /// while email confirmation is on. The form used to stay on screen with no
  /// sign that anything had happened, because go_router only redirects once a
  /// session exists.
  String? _confirmationSentTo;

  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _programmeController = TextEditingController();
  final _studentNumberController = TextEditingController();
  final _enrolmentYearController = TextEditingController();
  final _graduationYearController = TextEditingController();
  final _companyNameController = TextEditingController();
  final _industryController = TextEditingController();
  final _locationController = TextEditingController();

  static final _tabs = ['Student', 'Alumni', 'Employer'];
  static final _tabIcons = [Icons.school_outlined, Icons.workspace_premium_outlined, Icons.apartment_outlined];

  // No campuses lookup table exists (education.campus is free text). A fixed
  // list keeps the spelling consistent, which matters now that the campus is
  // saved and programme comparisons group students by what they entered.
  static const _campuses = ['Braamfontein', 'Cape Town', 'Durban', 'Pretoria', 'Nelspruit', 'Vereeniging'];
  String _campus = _campuses.first;

  static final _fourDigits = RegExp(r'^\d{4}$');

  List<TextEditingController> get _controllers => [
        _fullNameController,
        _emailController,
        _passwordController,
        _programmeController,
        _studentNumberController,
        _enrolmentYearController,
        _graduationYearController,
        _companyNameController,
        _industryController,
        _locationController,
      ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  // Tab 0/1/2 -> the backend's SignupRole (distinct from the cosmetic
  // RichfieldRole used for login-screen hint text). 'Employer' maps to
  // 'business', matching supabase/migrations' user_role enum.
  SignupRole get _signupRole {
    switch (_tab) {
      case 1:
        return SignupRole.alumni;
      case 2:
        return SignupRole.business;
      default:
        return SignupRole.student;
    }
  }

  String _text(TextEditingController controller) => controller.text.trim();

  String? _yearProblem(String label, TextEditingController controller, {required bool required}) {
    final value = _text(controller);
    if (value.isEmpty) return required ? '$label is required.' : null;
    final year = int.tryParse(value);
    final latest = DateTime.now().year + 8;
    if (!_fourDigits.hasMatch(value) || year == null || year < 1970 || year > latest) {
      return '$label must be a year between 1970 and $latest.';
    }
    return null;
  }

  String? _yearOrderProblem() {
    final started = int.tryParse(_text(_enrolmentYearController));
    final graduated = int.tryParse(_text(_graduationYearController));
    if (started != null && graduated != null && graduated < started) {
      return "Graduation year can't be before the year you started.";
    }
    return null;
  }

  /// The first thing missing or invalid for the selected account type. The
  /// required fields are the ones migration 028 needs to create the row: a
  /// student's education (programme, campus, start year), an alumnus's
  /// verification claim (student number, programme, campus, graduation year)
  /// and a business profile (company name).
  String? _validate() {
    if (_text(_fullNameController).isEmpty) return 'Enter your full name.';
    if (_text(_emailController).isEmpty) return 'Enter your email address.';
    switch (_tab) {
      case 0:
        if (_text(_programmeController).isEmpty) return 'Enter your programme.';
        return _yearProblem('Year started', _enrolmentYearController, required: true) ??
            _yearProblem('Graduation year', _graduationYearController, required: false) ??
            _yearOrderProblem();
      case 1:
        if (_text(_studentNumberController).isEmpty) return 'Enter the student number you studied under.';
        if (_text(_programmeController).isEmpty) return 'Enter the programme you completed.';
        return _yearProblem('Year started', _enrolmentYearController, required: false) ??
            _yearProblem('Graduation year', _graduationYearController, required: true) ??
            _yearOrderProblem();
      default:
        if (_text(_companyNameController).isEmpty) return 'Enter your company name.';
        return null;
    }
  }

  /// Only the fields this account type's form shows, and only filled-in ones.
  Map<String, Object> _details() {
    final details = <String, Object>{'registration_consent': true};
    void put(String key, TextEditingController controller) {
      final value = _text(controller);
      if (value.isNotEmpty) details[key] = value;
    }

    if (_tab == 2) {
      put('company_name', _companyNameController);
      put('industry', _industryController);
      put('location', _locationController);
    } else {
      put('programme', _programmeController);
      details['campus'] = _campus;
      put('enrolment_year', _enrolmentYearController);
      put('graduation_year', _graduationYearController);
      if (_tab == 1) put('student_number', _studentNumberController);
    }
    return details;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _errorMessage = problem);
      return;
    }

    // Naive split of "Full name" into first/last on the first space —
    // a hackathon-pace shortcut, not a real name-parsing solution.
    final fullName = _text(_fullNameController);
    final spaceIndex = fullName.indexOf(' ');
    final firstName = spaceIndex == -1 ? (fullName.isEmpty ? null : fullName) : fullName.substring(0, spaceIndex);
    final lastName = spaceIndex == -1 ? null : fullName.substring(spaceIndex + 1).trim();
    final email = _text(_emailController);

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final response = await widget.authService.signUp(
        email: email,
        password: _passwordController.text,
        role: _signupRole,
        firstName: firstName,
        lastName: lastName,
        details: _details(),
      );
      // A session only comes back if email confirmation is switched off, in
      // which case go_router's redirect takes over on its own.
      if (response.session == null && mounted) {
        setState(() => _confirmationSentTo = email);
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = AuthErrorMapper.fromAny(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final confirmationSentTo = _confirmationSentTo;
    return Scaffold(
      backgroundColor: AppColors.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceContainerLow,
        elevation: 0,
        foregroundColor: AppColors.onSurface,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(AppSpace.base),
          child: confirmationSentTo == null ? _form() : _confirmationView(confirmationSentTo),
        ),
      ),
    );
  }

  Widget _confirmationView(String email) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: AppSpace.xl),
        Icon(Icons.mark_email_read_outlined, size: 56, color: AppColors.primary),
        SizedBox(height: AppSpace.md),
        Text('Check your inbox', textAlign: TextAlign.center, style: AppText.headlineLg()),
        SizedBox(height: AppSpace.sm),
        Text(
          'We sent a confirmation link to $email. Open it, then come back and sign in.',
          textAlign: TextAlign.center,
          style: AppText.bodyMd(color: AppColors.onSurfaceVariant),
        ),
        if (_tab != 0) ...[
          SizedBox(height: AppSpace.md),
          RoundedCard(
            child: Text(
              _tab == 1
                  ? 'After you confirm, a Richfield administrator checks your student number and graduation details. You can use the app once they approve your account.'
                  : 'After you confirm, a Richfield administrator reviews your company. You can use the app once they approve your account.',
              style: AppText.bodyMd(),
            ),
          ),
        ],
        SizedBox(height: AppSpace.lg),
        PrimaryButton(
          label: 'Back to sign in',
          icon: Icons.login,
          onPressed: () => context.go('/login'),
        ),
      ],
    );
  }

  String get _howItWorks => switch (_tab) {
        1 => 'A Richfield administrator checks your student number and graduation year before your account is activated.',
        2 => 'A Richfield administrator reviews your company before your account is activated.',
        _ => 'Confirm your student email from your inbox, then sign in. There is no approval step.',
      };

  String get _consentText {
    final review = switch (_tab) {
      1 => ', and to a Richfield administrator checking my student details',
      2 => ', and to a Richfield administrator reviewing my company details',
      _ => '',
    };
    return 'I consent to Richfield Connect storing the details above to run my account and show my profile to other members$review, in line with POPIA.';
  }

  Widget _form() {
    final muted = AppText.bodySm(color: AppColors.onSurfaceVariant);
    final (emailLabel, emailHint, emailNote) = switch (_tab) {
      1 => ('Email address', 'you@example.com', 'Any address you check. You don\'t need your old student inbox.'),
      2 => ('Work email', 'you@company.co.za', 'Use your company address so the administrator can see who you work for.'),
      _ => (
          'Student email',
          'you@my.richfield.ac.za',
          'Must end in @my.richfield.ac.za, @richfield.ac.za, @my.aaa.ac.za or @aaa.ac.za.',
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('RICHFIELD GRADUATE NETWORK',
                      style: AppText.labelBadge(color: AppColors.primary)),
                  Text('Join the Talent Nexus', style: AppText.headlineLg()),
                ],
              ),
            ),
            Pill(
              text: 'ACCREDITED',
              background: AppColors.successGreenBg,
              foreground: AppColors.successGreen,
            ),
          ],
        ),
        SizedBox(height: AppSpace.sm),
        Text(
          'Build a portfolio, find internships and graduate roles, and connect with Richfield alumni and recruiters.',
          style: AppText.bodyMd(color: AppColors.onSurfaceVariant),
        ),
        SizedBox(height: AppSpace.base),
        RoundedCard(
          padding: EdgeInsets.all(4),
          border: Border.all(color: Colors.transparent),
          color: AppColors.surfaceContainerHigh.withOpacity(0.5),
          child: Row(
            children: List.generate(_tabs.length, (i) {
              final selected = _tab == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _tab = i;
                    _errorMessage = null;
                  }),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.surfaceContainerLowest : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Column(
                      children: [
                        Icon(_tabIcons[i],
                            size: 18,
                            color: selected ? AppColors.primary : AppColors.onSurfaceVariant),
                        SizedBox(height: 2),
                        Text(_tabs[i],
                            style: AppText.labelMd(
                                color: selected ? AppColors.primary : AppColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        SizedBox(height: AppSpace.base),
        // Was "Instant institutional database match via student email" with
        // an 'ID VERIFIED' pill. No such lookup exists; this says what does
        // happen for each account type.
        RoundedCard(
          color: AppColors.secondaryContainer.withOpacity(0.2),
          border: Border.all(color: Colors.transparent),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(_tabIcons[_tab], color: Colors.white, size: 18),
              ),
              SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_tabs[_tab]} registration', style: AppText.labelLg()),
                    Text(_howItWorks, style: muted),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: AppSpace.base),
        _labeledField('Full name', 'e.g. Sipho Nhlanhla Dlamini', Icons.person_outline,
            controller: _fullNameController),
        SizedBox(height: AppSpace.md),
        ..._accountTypeFields(),
        Text(emailLabel, style: AppText.labelLg()),
        SizedBox(height: 6),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.alternate_email, size: 18),
            hintText: emailHint,
            filled: true,
            fillColor: AppColors.surfaceContainerLowest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              borderSide: BorderSide(color: AppColors.outlineVariant),
            ),
          ),
        ),
        SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_tab == 0 ? Icons.lock_outline : Icons.info_outline, size: 12, color: AppColors.onSurfaceVariant),
            SizedBox(width: 4),
            Expanded(child: Text(emailNote, style: muted)),
          ],
        ),
        SizedBox(height: AppSpace.md),
        _labeledField('Password', 'At least 8 characters', Icons.lock_outline,
            controller: _passwordController, obscureText: true),
        SizedBox(height: AppSpace.base),
        // The old text also consented to "cross-matching my identity with
        // institutional registrar databases", which nothing does.
        CheckboxListTile(
          value: _agreed,
          onChanged: (v) => setState(() => _agreed = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(_consentText, style: AppText.bodySm()),
        ),
        if (_errorMessage != null) ...[
          Padding(
            padding: EdgeInsets.only(bottom: AppSpace.sm),
            child: Text(_errorMessage!, style: AppText.bodySm(color: AppColors.error)),
          ),
        ],
        SizedBox(height: AppSpace.sm),
        PrimaryButton(
          label: _submitting ? 'Creating account…' : 'Create ${_tabs[_tab].toLowerCase()} account',
          icon: Icons.how_to_reg_outlined,
          onPressed: (_agreed && !_submitting) ? _submit : null,
        ),
        SizedBox(height: AppSpace.base),
      ],
    );
  }

  /// Student and alumni fields become an education row (and, for alumni, the
  /// verification claim an administrator approves); employer fields become the
  /// business profile. All of these used to be discarded on submit.
  List<Widget> _accountTypeFields() {
    Widget gap() => SizedBox(height: AppSpace.md);

    if (_tab == 2) {
      return [
        _labeledField('Company name', 'e.g. Acme Digital (Pty) Ltd', Icons.apartment_outlined,
            controller: _companyNameController),
        gap(),
        _labeledField('Industry (optional)', 'Software engineering and data', Icons.business_center_outlined,
            controller: _industryController),
        gap(),
        _labeledField('Company location (optional)', 'Sandton, Johannesburg', Icons.location_on_outlined,
            controller: _locationController),
        gap(),
      ];
    }

    final alumni = _tab == 1;
    return [
      if (alumni) ...[
        _labeledField('Student number', 'The number you studied under', Icons.badge_outlined,
            controller: _studentNumberController),
        gap(),
      ],
      _labeledField(alumni ? 'Programme completed' : 'Programme', 'BSc Information Technology', Icons.school_outlined,
          controller: _programmeController),
      gap(),
      _campusDropdown(),
      gap(),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _labeledField(alumni ? 'Year started (optional)' : 'Year started', alumni ? '2017' : '2024', Icons.event_outlined,
                controller: _enrolmentYearController, keyboardType: TextInputType.number),
          ),
          SizedBox(width: AppSpace.sm),
          Expanded(
            child: _labeledField(alumni ? 'Graduation year' : 'Graduating (optional)', alumni ? '2021' : '2027',
                Icons.calendar_today_outlined,
                controller: _graduationYearController, keyboardType: TextInputType.number),
          ),
        ],
      ),
      gap(),
    ];
  }

  Widget _labeledField(String label, String hint, IconData icon,
      {TextEditingController? controller, bool obscureText = false, TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.labelLg()),
        SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18),
            hintText: hint,
            filled: true,
            fillColor: AppColors.surfaceContainerLowest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              borderSide: BorderSide(color: AppColors.outlineVariant),
            ),
          ),
        ),
      ],
    );
  }

  Widget _campusDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Campus', style: AppText.labelLg()),
        SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _campus,
          items: _campuses
              .map((c) => DropdownMenuItem(value: c, child: Text(c, style: AppText.bodyMd())))
              .toList(),
          onChanged: (v) => setState(() => _campus = v ?? _campus),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceContainerLowest,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              borderSide: BorderSide(color: AppColors.outlineVariant),
            ),
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// SECTION 7 — ROOT SHELL (bottom navigation)
// =====================================================================

class AdminDashboardScreen extends StatefulWidget {
  AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _service = AdminAnalyticsService(Supabase.instance.client);
  AdminOverview? _overview;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final overview = await _service.load();
      if (mounted) setState(() => _overview = overview);
    } catch (e) {
      if (mounted) setState(() => _error = AuthErrorMapper.fromAny(e));
    }
  }

  String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

  Widget _stat(int value, String label) => Expanded(
        child: Column(
          children: [
            Text('$value', style: AppText.headlineMd(color: AppColors.primary)),
            Text(label, style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final o = _overview;
    final pendingBusinesses = o?.businessesByStatus['pending'] ?? 0;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(AppSpace.base, AppSpace.sm, AppSpace.base, 24),
        children: [
          RichfieldHeader(
            title: 'Admin Overview',
            subtitle: 'RICHFIELD STAFF',
            onAvatarTap: () => _openAccountMenu(context, AuthService(Supabase.instance.client)),
          ),
          if (_error != null) ...[
            Text(_error!, style: AppText.bodySm(color: AppColors.error)),
            TextButton(onPressed: _load, child: Text('Try again')),
          ] else if (o == null)
            Padding(
              padding: EdgeInsets.all(AppSpace.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            SectionHeader(title: 'Members'),
            _metricGrid([
              ['${o.usersByRole['student'] ?? 0}', 'Students', Icons.school_outlined],
              ['${o.usersByRole['alumni'] ?? 0}', 'Alumni', Icons.workspace_premium_outlined],
              ['${o.usersByRole['business'] ?? 0}', 'Businesses', Icons.business_center_outlined],
              ['${o.monthlyActiveUsers}', 'Active this month', Icons.insights_outlined],
            ]),
            SizedBox(height: AppSpace.base),
            SectionHeader(title: 'Needs attention'),
            _checkRow('Business accounts awaiting approval', '$pendingBusinesses pending',
                done: pendingBusinesses == 0),
            _checkRow('Alumni verification claims', '${o.pendingAlumniClaims} pending',
                done: o.pendingAlumniClaims == 0),
            _checkRow('Flagged content', _plural(o.flaggedContent, 'report'), done: o.flaggedContent == 0),
            SizedBox(height: AppSpace.base),
            SectionHeader(title: 'Content'),
            RoundedCard(
              child: Row(
                children: [
                  _stat(o.posts, 'Posts'),
                  _stat(o.videos, 'Videos'),
                  _stat(o.opportunities, 'Opportunities'),
                ],
              ),
            ),
            SizedBox(height: AppSpace.base),
            RoundedCard(
              child: Row(
                children: [
                  Icon(Icons.desktop_windows_outlined, color: AppColors.secondary),
                  SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      'Approvals, moderation and announcements are handled in the Richfield Connect web admin console.',
                      style: AppText.bodyMd(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class BusinessDashboardScreen extends StatefulWidget {
  BusinessDashboardScreen({super.key});

  @override
  State<BusinessDashboardScreen> createState() => _BusinessDashboardScreenState();
}

class _BusinessDashboardScreenState extends State<BusinessDashboardScreen> {
  final _authService = AuthService(Supabase.instance.client);
  final _analytics = BusinessAnalyticsService(Supabase.instance.client);

  bool _loading = true;
  String? _error;
  int _totalApplicants = 0;
  List<MapEntry<String, int>> _topSkills = [];
  List<Map<String, dynamic>> _engagement = [];
  String _companyName = '';
  bool _companyComplete = false;
  bool _approved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pipeline = await _analytics.fetchApplicantPipeline();
      final skills = await _analytics.fetchSkillDistribution();
      final engagement = await _analytics.fetchListingEngagement();

      var companyName = '';
      var companyComplete = false;
      var approved = false;
      final businessId = _authService.currentUser?.id;
      if (businessId != null) {
        final client = Supabase.instance.client;
        final rows = await Future.wait<dynamic>([
          client
              .from('business_profiles')
              .select('company_name, industry, location, description')
              .eq('profile_id', businessId)
              .maybeSingle(),
          client.from('profiles').select('account_status').eq('id', businessId).maybeSingle(),
        ]);
        final bp = rows[0] as Map<String, dynamic>?;
        final profile = rows[1] as Map<String, dynamic>?;
        companyName = (bp?['company_name'] as String?) ?? '';
        companyComplete = ['company_name', 'industry', 'location', 'description']
            .every((key) => ((bp?[key] as String?) ?? '').trim().isNotEmpty);
        approved = profile?['account_status'] == 'active';
      }

      final total = pipeline.fold<int>(
          0, (sum, r) => sum + ((r['applicant_count'] as num?)?.toInt() ?? 0));
      final skillTotals = <String, int>{};
      for (final row in skills) {
        final name = row['skill_name'] as String?;
        if (name == null) continue;
        skillTotals[name] = (skillTotals[name] ?? 0) + ((row['candidate_count'] as num?)?.toInt() ?? 0);
      }
      final topSkills = skillTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

      if (!mounted) return;
      setState(() {
        _totalApplicants = total;
        _topSkills = topSkills.take(3).toList();
        _engagement = engagement;
        _companyName = companyName;
        _companyComplete = companyComplete;
        _approved = approved;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AuthErrorMapper.fromAny(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(AppSpace.base, AppSpace.sm, AppSpace.base, 24),
      children: [
        RichfieldHeader(
          title: 'Business Analytics',
          subtitle: 'ENTERPRISE PORTAL',
          onAvatarTap: () => _openAccountMenu(context, _authService),
        ),
        PrimaryButton(
          label: 'Post New Opportunity',
          icon: Icons.add_business_outlined,
          onPressed: () async {
            final posted = await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => PostOpportunityScreen()),
            );
            if (posted == true) _load();
          },
        ),
        SizedBox(height: AppSpace.base),
        if (!_loading && _error == null) ...[
          _dashboardBanner(
              _approved
                  ? (_companyName.isEmpty ? 'Approved partner' : '$_companyName • Approved partner')
                  : 'Awaiting Richfield approval',
              _approved ? AppColors.secondary : AppColors.tertiary),
          SizedBox(height: AppSpace.base),
          SectionHeader(title: 'Account Status'),
          // These were three hardcoded ticks: 'CIPC Registration Verified',
          // 'Work Email Domain Verified' showing the literal '@discovery.co.za'
          // on every business account, and an MoA 'In review'. Nothing in the
          // schema records any of those, so the rows show what it does record.
          _checkRow('Approved by a Richfield administrator',
              _approved ? 'Account active' : 'Waiting for an administrator to review your account',
              done: _approved),
          _checkRow('Company profile',
              _companyComplete ? 'Name, industry, location and description on file' : 'Industry, location or description missing',
              done: _companyComplete),
          SizedBox(height: AppSpace.base),
        ],
        SectionHeader(title: 'Talent Analytics'),
        if (_loading)
          Padding(
            padding: EdgeInsets.all(AppSpace.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (!_loading && _error != null)
          Text(_error!, style: AppText.bodySm(color: AppColors.error)),
        if (!_loading && _error == null)
          RoundedCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total Applicant Pipeline', style: AppText.labelLg()),
                Text('$_totalApplicants', style: AppText.displayLgMobile(color: AppColors.primary)),
                Text('Active Candidates', style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                SizedBox(height: AppSpace.md),
                Text('Candidate Skill Distribution', style: AppText.labelLg()),
                if (_topSkills.isEmpty)
                  Text('No applications yet.', style: AppText.bodySm(color: AppColors.onSurfaceVariant))
                else
                  ..._topSkills.map((e) => _skillBar(
                      e.key, _totalApplicants == 0 ? 0.0 : (e.value / _totalApplicants).clamp(0.0, 1.0))),
                SizedBox(height: AppSpace.md),
                // Replaces the mock's fabricated "7-day" trend chart:
                // get_business_listing_engagement() returns one row per
                // opportunity (view/application counts), not a daily time
                // series, so a real per-listing summary is the honest
                // equivalent rather than faking a trend against real totals.
                Text('Listing Engagement', style: AppText.labelLg()),
                if (_engagement.isEmpty)
                  Text('No listings yet.', style: AppText.bodySm(color: AppColors.onSurfaceVariant))
                else
                  ..._engagement.map((row) => GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ApplicantsScreen(
                              opportunityId: row['opportunity_id'] as String,
                              listingTitle: row['title'] as String? ?? 'Listing',
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.only(top: AppSpace.sm),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: Text(row['title'] as String? ?? '', style: AppText.bodySm())),
                              Text(
                                  '${row['application_count']}/${row['view_count']} views • ${row['engagement_rate']}%',
                                  style: AppText.labelMd()),
                            ],
                          ),
                        ),
                      )),
              ],
            ),
          ),
      ],
    );
  }
}

Widget _dashboardBanner(String text, Color color) => RoundedCard(
      color: color.withOpacity(.12),
      border: Border.all(color: Colors.transparent),
      child: Row(children: [Icon(Icons.circle, size: 9, color: color), SizedBox(width: 8), Expanded(child: Text(text, style: AppText.labelMd(color: color)))]),
    );

Widget _metricGrid(List<List<Object>> metrics) => GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpace.sm,
      crossAxisSpacing: AppSpace.sm,
      childAspectRatio: 1.45,
      children: metrics.map((metric) => RoundedCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(metric[2] as IconData, color: AppColors.secondary), Spacer(), Text(metric[0] as String, style: AppText.headlineMd()), Text(metric[1] as String, style: AppText.labelMd(color: AppColors.onSurfaceVariant))]))).toList(),
    );

/// A status line with a real state behind it: a green check when [done], a
/// pending icon when not. The old version chose its icon by looking for the
/// substring 'MoA' in the title, on rows whose "verified" state was invented.
Widget _checkRow(String title, String detail, {required bool done}) => Padding(
      padding: EdgeInsets.only(bottom: AppSpace.sm),
      child: RoundedCard(child: Row(children: [Icon(done ? Icons.check_circle : Icons.pending_outlined, color: done ? AppColors.successGreen : AppColors.tertiary), SizedBox(width: AppSpace.sm), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: AppText.labelMd()), Text(detail, style: AppText.bodySm(color: AppColors.onSurfaceVariant))]))])),
    );

Widget _skillBar(String label, double value) => Padding(padding: EdgeInsets.only(top: AppSpace.sm), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: AppText.bodySm()), Text('${(value * 100).round()}%', style: AppText.labelMd())]), SizedBox(height: 4), LinearProgressIndicator(value: value, color: AppColors.secondary, backgroundColor: AppColors.surfaceContainerHigh)]));

class PostOpportunityScreen extends StatefulWidget {
  PostOpportunityScreen({super.key});

  @override
  State<PostOpportunityScreen> createState() => _PostOpportunityScreenState();
}

class _PostOpportunityScreenState extends State<PostOpportunityScreen> {
  final _authService = AuthService(Supabase.instance.client);
  final _jobsService = JobsService(Supabase.instance.client);

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _skillsController = TextEditingController();
  final _programmeController = TextEditingController();
  String _type = 'internship';
  bool _submitting = false;

  static const _typeOptions = ['internship', 'learnership', 'part_time', 'graduate_vacancy'];
  static const _typeLabels = {
    'internship': 'Internship',
    'learnership': 'Learnership',
    'part_time': 'Part-time',
    'graduate_vacancy': 'Graduate Vacancy',
  };

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _skillsController.dispose();
    _programmeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    if (title.isEmpty || description.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Title and description are required.')));
      return;
    }

    final businessId = _authService.currentUser?.id;
    if (businessId == null) return;

    final skills = _skillsController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final programme = _programmeController.text.trim();

    setState(() => _submitting = true);
    try {
      await _jobsService.postOpportunity(
        businessId: businessId,
        title: title,
        description: description,
        opportunityType: _type,
        requiredSkills: skills,
        programmeFilter: programme.isEmpty ? null : programme,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submitted for admin approval.'), duration: Duration(seconds: 2)),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthErrorMapper.fromAny(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Post New Opportunity')),
      body: ListView(
        padding: EdgeInsets.all(AppSpace.base),
        children: [
          Text('Title', style: AppText.labelLg()),
          SizedBox(height: 6),
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              hintText: 'e.g. Junior Software Developer Internship',
              filled: true,
              fillColor: AppColors.surfaceContainerLow,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide.none),
            ),
          ),
          SizedBox(height: AppSpace.md),
          Text('Description', style: AppText.labelLg()),
          SizedBox(height: 6),
          TextField(
            controller: _descriptionController,
            minLines: 4,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: 'What will this person do? What are you looking for?',
              filled: true,
              fillColor: AppColors.surfaceContainerLow,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide.none),
            ),
          ),
          SizedBox(height: AppSpace.md),
          Text('Type', style: AppText.labelLg()),
          SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _type,
            items: _typeOptions
                .map((t) => DropdownMenuItem(value: t, child: Text(_typeLabels[t]!)))
                .toList(),
            onChanged: (v) => setState(() => _type = v ?? _type),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surfaceContainerLow,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide.none),
            ),
          ),
          SizedBox(height: AppSpace.md),
          Text('Required Skills (comma-separated)', style: AppText.labelLg()),
          SizedBox(height: 6),
          TextField(
            controller: _skillsController,
            decoration: InputDecoration(
              hintText: 'e.g. React, SQL, Python',
              filled: true,
              fillColor: AppColors.surfaceContainerLow,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide.none),
            ),
          ),
          SizedBox(height: AppSpace.md),
          Text('Programme Filter (optional)', style: AppText.labelLg()),
          SizedBox(height: 6),
          TextField(
            controller: _programmeController,
            decoration: InputDecoration(
              hintText: 'e.g. BSc Information Technology',
              filled: true,
              fillColor: AppColors.surfaceContainerLow,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide.none),
            ),
          ),
          SizedBox(height: AppSpace.xl),
          PrimaryButton(
            label: 'Submit for Approval',
            icon: Icons.send_outlined,
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }
}

/// Read-only list of who applied to one of the business's own listings.
/// No accept/reject affordance here by design - just visibility.
class ApplicantsScreen extends StatefulWidget {
  final String opportunityId;
  final String listingTitle;
  ApplicantsScreen({super.key, required this.opportunityId, required this.listingTitle});

  @override
  State<ApplicantsScreen> createState() => _ApplicantsScreenState();
}

class _ApplicantsScreenState extends State<ApplicantsScreen> {
  final _jobsService = JobsService(Supabase.instance.client);
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _applicants = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _jobsService.fetchApplicants(opportunityId: widget.opportunityId);
      if (!mounted) return;
      setState(() {
        _applicants = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AuthErrorMapper.fromAny(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.listingTitle)),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: EdgeInsets.all(AppSpace.base),
                  child: Text(_error!, style: AppText.bodySm(color: AppColors.error)),
                )
              : _applicants.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(AppSpace.base),
                      child: Text('No applicants yet.',
                          style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.all(AppSpace.base),
                      itemCount: _applicants.length,
                      separatorBuilder: (_, __) => SizedBox(height: AppSpace.sm),
                      itemBuilder: (_, i) => _applicantRow(_applicants[i]),
                    ),
    );
  }

  Widget _applicantRow(Map<String, dynamic> row) {
    final profile = row['profiles'] as Map<String, dynamic>?;
    final first = profile?['first_name'] as String? ?? '';
    final last = profile?['last_name'] as String? ?? '';
    final name = (profile == null) ? 'Former / inactive account' : '$first $last'.trim();
    final headline = profile?['professional_headline'] as String?;
    final initials = (first.isNotEmpty ? first[0] : '') + (last.isNotEmpty ? last[0] : '');
    final status = row['status'] as String? ?? 'submitted';
    final appliedAt = DateTime.tryParse(row['applied_at'] as String? ?? '');

    return RoundedCard(
      child: Row(
        children: [
          InitialsAvatar(initials: initials.isEmpty ? '?' : initials.toUpperCase()),
          SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.isEmpty ? 'Unnamed applicant' : name, style: AppText.labelLg()),
                if (headline != null && headline.isNotEmpty)
                  Text(headline, style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                if (appliedAt != null)
                  Text('Applied ${appliedAt.day}/${appliedAt.month}/${appliedAt.year}',
                      style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
          _statusPill(status),
        ],
      ),
    );
  }

  Widget _statusPill(String status) {
    switch (status) {
      case 'accepted':
        return Pill(
            text: 'Accepted',
            background: AppColors.successGreenBg,
            foreground: AppColors.successGreen);
      case 'rejected':
        return Pill(
            text: 'Rejected', background: AppColors.errorContainer, foreground: AppColors.error);
      case 'reviewed':
        return Pill(
            text: 'Reviewed',
            background: AppColors.secondaryContainer,
            foreground: AppColors.secondary);
      default:
        return Pill(
            text: 'Submitted',
            background: AppColors.surfaceContainerHigh,
            foreground: AppColors.onSurfaceVariant);
    }
  }
}

class BusinessHubScreen extends StatelessWidget {
  BusinessHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(tabs: [Tab(text: 'Feed'), Tab(text: 'Analytics')], labelColor: AppColors.primary),
          Expanded(child: TabBarView(children: [FeedScreen(), BusinessDashboardScreen()])),
        ],
      ),
    );
  }
}

class AdminHubScreen extends StatelessWidget {
  AdminHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(tabs: [Tab(text: 'Feed'), Tab(text: 'Reports')], labelColor: AppColors.primary),
          Expanded(child: TabBarView(children: [FeedScreen(), AdminDashboardScreen()])),
        ],
      ),
    );
  }
}

class RootShell extends StatefulWidget {
  final RichfieldRole role;
  final AuthService authService;

  RootShell({super.key, required this.role, required this.authService});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const _networkTab = 2;

  // Rubric Section 6, item 4: "First-time users receive an interactive
  // app tutorial." Before this, OnboardingTourOverlay only ever launched
  // manually from the account menu ("Take the Onboarding Tour") — nothing
  // triggered it automatically, so a first-time user who never opened
  // that menu would never see it at all.
  static const _tourSeenKey = 'richfield_onboarding_tour_seen';

  StreamSubscription<Map<String, dynamic>>? _alertSubscription;

  @override
  void initState() {
    super.initState();
    // One realtime (WebSocket) channel for the signed-in user, shared by the
    // Messages badge, the bell, open chats and the Network screen — see
    // services/realtime_hub.dart. Released when go_router swaps the shell
    // for the login screen on sign-out.
    RealtimeHub.instance.retain();
    _alertSubscription = RealtimeHub.instance.notifications.listen(_showInAppAlert);

    // addPostFrameCallback, not a direct call here: _startOnboardingTour
    // does Navigator.of(context).push(...), and calling that before this
    // widget's first frame has actually built is exactly the kind of
    // "Navigator operation requested with a context that does not
    // include a Navigator" crash this avoids.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTour());
  }

  @override
  void dispose() {
    _alertSubscription?.cancel();
    RealtimeHub.instance.release();
    super.dispose();
  }

  Future<void> _maybeShowTour() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadySeen = prefs.getBool(_tourSeenKey) ?? false;
    if (alreadySeen || !mounted) return;

    // Set the flag before showing, not after dismissal — the manual
    // "Take the Onboarding Tour" menu item is still there as a permanent
    // fallback, so the cost of marking it seen a touch early is low, and
    // it means repeatedly relaunching the app mid-testing (Keshav's
    // actual workflow tonight) doesn't re-trigger it on every restart.
    await prefs.setBool(_tourSeenKey, true);
    if (!mounted) return;
    await _startOnboardingTour(context);

    // Rubric 6.1: the tour explains the app, then Career AI walks a new
    // student or alumnus through actually filling in their profile, one
    // missing section at a time. Offered rather than forced — "Later" leaves
    // it on the Portfolio sparkle button and in the account menu.
    final hasCareerProfile =
        widget.role == RichfieldRole.student || widget.role == RichfieldRole.alumni;
    if (!hasCareerProfile || !mounted) return;
    final start = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(Icons.auto_awesome, color: AppColors.primary),
        title: Text('Set up your profile with AI?'),
        content: Text(
          'Richfield Career AI looks at what your profile is missing and walks you through it step by step.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Start'),
          ),
        ],
      ),
    );
    if (start == true && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AiAssistantScreen(guided: true)),
      );
    }
  }

  /// In-app alert for anything that arrives while the app is open
  /// (guidelines 2.8). Skipped for a message from the person whose chat is
  /// already on screen — the message appearing there is the alert.
  void _showInAppAlert(Map<String, dynamic> row) {
    if (!mounted) return;
    final notification = AppNotification.fromRow(row);
    if (notification.type == 'new_message' &&
        notification.payload['sender_id'] == RealtimeHub.instance.activeChatPartnerId) {
      return;
    }
    final text = notification.body.isEmpty
        ? notification.title
        : '${notification.title} — ${notification.body}';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
        content: Row(
          children: [
            Icon(notificationIcon(notification.type), size: 18, color: AppColors.inverseOnSurface),
            SizedBox(width: AppSpace.sm),
            Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis)),
          ],
        ),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => openNotificationTarget(context, notification),
        ),
      ));
  }

  void _openMenu() => _openAccountMenu(context, widget.authService);

  List<Widget> get _screens => [
        widget.role == RichfieldRole.admin
            ? AdminHubScreen()
            : widget.role == RichfieldRole.corporate
                ? BusinessHubScreen()
                : FeedScreen(),
        JobsScreen(),
        NetworkScreen(onAvatarTap: _openMenu),
        MessagesScreen(
          onAvatarTap: _openMenu,
          onFindPeople: () => setState(() => _index = _networkTab),
        ),
        PortfolioScreen(authService: widget.authService),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _index, children: _screens)),
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: RealtimeHub.instance.unreadMessages,
        builder: (context, unread, _) => BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _index,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.onSurfaceVariant,
          selectedLabelStyle: AppText.labelMd(color: AppColors.primary),
          unselectedLabelStyle: AppText.labelMd(color: AppColors.onSurfaceVariant),
          onTap: (i) => setState(() => _index = i),
          items: [
            BottomNavigationBarItem(icon: Icon(Icons.dynamic_feed_outlined), label: 'Feed'),
            BottomNavigationBarItem(icon: Icon(Icons.work_outline), label: 'Jobs'),
            BottomNavigationBarItem(icon: Icon(Icons.hub_outlined), label: 'Network'),
            BottomNavigationBarItem(
              icon: Badge(
                isLabelVisible: unread > 0,
                label: Text(unread > 99 ? '99+' : '$unread'),
                child: Icon(Icons.chat_bubble_outline),
              ),
              label: 'Messages',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.badge_outlined), label: 'Portfolio'),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// SECTION 8 — FEED SCREEN
// =====================================================================

class FeedScreen extends StatefulWidget {
  FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  int _filter = 0;
  final Set<String> _dismissedPosts = <String>{};

  /// Applied to the loaded posts by _visiblePosts. None of the chips used to
  /// filter anything, and the third was 'Graduate Jobs' in a list of posts.
  static const _filters = ['All updates', 'Career reels', 'Photos'];

  /// Upcoming published events, soonest first. The banner shows the first
  /// and links to the rest; an empty list hides it.
  List<Map<String, dynamic>> _upcomingEvents = [];
  bool _eventDismissed = false;

  final _authService = AuthService(Supabase.instance.client);
  final _feedService = FeedService(Supabase.instance.client);
  final _mediaService = MediaService(Supabase.instance.client);
  bool _loadingPosts = true;
  String? _postsError;
  List<FeedPost> _posts = [];

  /// Post ids this user has already reposted, loaded alongside the feed so
  /// the Repost button paints in the right state on first frame instead of
  /// defaulting to off and flipping a moment later.
  Set<String> _repostedIds = <String>{};

  /// Post ids this user has liked, loaded the same way.
  Set<String> _reactedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _loadEvents();
  }

  /// The banner is optional: if this fails the feed shows no banner rather
  /// than an error above posts that loaded fine.
  Future<void> _loadEvents() async {
    try {
      final events = await _feedService.fetchUpcomingEvents();
      if (mounted) setState(() => _upcomingEvents = events);
    } catch (_) {
      if (mounted) setState(() => _upcomingEvents = []);
    }
  }

  Future<void> _loadPosts() async {
    setState(() {
      _loadingPosts = true;
      _postsError = null;
    });
    try {
      final userId = _authService.currentUser?.id;

      // One round trip each, in parallel — the repost set is not worth a
      // second sequential wait before the feed can paint.
      final results = await Future.wait<Object>([
        _feedService.fetchRecentPosts(),
        if (userId != null) _feedService.fetchMyRepostedPostIds(userId),
        if (userId != null) _feedService.fetchMyReactedPostIds(userId),
      ]);

      final rows = results[0] as List<Map<String, dynamic>>;
      final reposted =
          results.length > 1 ? results[1] as Set<String> : <String>{};
      final reacted =
          results.length > 2 ? results[2] as Set<String> : <String>{};

      if (!mounted) return;
      setState(() {
        _repostedIds = reposted;
        _reactedIds = reacted;
        _posts = rows
            .map((row) => _feedPostFromRow(
                  row,
                  repostedIds: reposted,
                  reactedIds: reacted,
                  mediaService: _mediaService,
                ))
            .toList();
        _loadingPosts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _postsError = AuthErrorMapper.fromAny(e);
        _loadingPosts = false;
      });
    }
  }

  /// Optimistic toggle: flip the card immediately, then reconcile with the
  /// server. On failure we put the previous state back rather than leaving
  /// the UI showing a repost that does not exist in the database.
  Future<void> _toggleRepost(FeedPost post) async {
    final postId = post.id;
    final userId = _authService.currentUser?.id;
    if (postId == null || userId == null) return;

    final wasReposted = post.isReposted;

    void apply(bool reposted) {
      setState(() {
        if (reposted) {
          _repostedIds.add(postId);
        } else {
          _repostedIds.remove(postId);
        }
        _posts = _posts
            .map((p) => p.id == postId
                ? p.copyWith(
                    isReposted: reposted,
                    reactionCountC:
                        (p.reactionCountC + (reposted ? 1 : -1)).clamp(0, 1 << 30),
                  )
                : p)
            .toList();
      });
    }

    apply(!wasReposted);

    try {
      await _feedService.toggleRepost(
        postId: postId,
        userId: userId,
        currentlyReposted: wasReposted,
      );
    } catch (e) {
      if (!mounted) return;
      apply(wasReposted); // roll back
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AuthErrorMapper.fromAny(e))),
      );
    }
  }

  /// Same optimistic pattern as reposts. reactions allows one row per member
  /// per post, so a double tap can't count twice.
  Future<void> _toggleReaction(FeedPost post) async {
    final postId = post.id;
    final userId = _authService.currentUser?.id;
    if (postId == null || userId == null) return;

    final wasReacted = post.isReacted;

    void apply(bool reacted) {
      setState(() {
        if (reacted) {
          _reactedIds.add(postId);
        } else {
          _reactedIds.remove(postId);
        }
        _posts = _posts
            .map((p) => p.id == postId
                ? p.copyWith(
                    isReacted: reacted,
                    reactionCountA: (p.reactionCountA + (reacted ? 1 : -1)).clamp(0, 1 << 30),
                  )
                : p)
            .toList();
      });
    }

    apply(!wasReacted);

    try {
      await _feedService.toggleReaction(postId: postId, userId: userId, currentlyReacted: wasReacted);
    } catch (e) {
      if (!mounted) return;
      apply(wasReacted);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AuthErrorMapper.fromAny(e))),
      );
    }
  }

  void _openComments(FeedPost post) {
    final postId = post.id;
    if (postId == null) return;
    showCommentsSheet(
      context,
      postId: postId,
      onCountChanged: (count) {
        if (!mounted) return;
        setState(() {
          _posts = _posts.map((p) => p.id == postId ? p.copyWith(reactionCountB: count) : p).toList();
        });
      },
    );
  }

  void _reportPost(FeedPost post) {
    final postId = post.id;
    if (postId == null) return;
    showReportContentDialog(
      context,
      contentType: post.type == FeedPostType.video ? 'video' : 'post',
      contentId: postId,
    );
  }

  Future<void> _deletePost(FeedPost post) async {
    if (!await _confirmAndDeletePost(context, post)) return;
    if (!mounted) return;
    setState(() => _posts = _posts.where((p) => p.id != post.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => Future.wait([_loadPosts(), _loadEvents()]),
          child: ListView(
          padding: EdgeInsets.only(bottom: 90),
          children: [
            RichfieldHeader(
              title: 'Feed',
              subtitle: 'RICHFIELD VERIFIED',
              onAvatarTap: () => _openAccountMenu(context, _authService),
            ),
            if (_upcomingEvents.isNotEmpty && !_eventDismissed)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpace.base),
                child: _eventBanner(_upcomingEvents.first, total: _upcomingEvents.length),
              ),
            SizedBox(height: AppSpace.base),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpace.base),
              child: SectionHeader(title: 'Network Activity', trailing: null),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpace.base),
              child: SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _filters.length,
                  separatorBuilder: (_, __) => SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final selected = _filter == i;
                    return ChoiceChip(
                      label: Text(_filters[i]),
                      selected: selected,
                      onSelected: (_) => setState(() => _filter = i),
                      labelStyle: AppText.labelMd(
                          color: selected ? AppColors.onPrimary : AppColors.onSurfaceVariant),
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.surfaceContainerLowest,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        side: BorderSide(
                            color: selected ? Colors.transparent : AppColors.outlineVariant),
                      ),
                    );
                  },
                ),
              ),
            ),
            SizedBox(height: AppSpace.md),
            if (_loadingPosts)
              Padding(
                padding: EdgeInsets.all(AppSpace.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_loadingPosts && _postsError != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpace.base),
                child: Text(_postsError!, style: AppText.bodySm(color: AppColors.error)),
              ),
            if (!_loadingPosts && _postsError == null && _visiblePosts.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpace.base),
                child: Text(
                  switch (_filter) {
                    1 => 'No career reels yet.',
                    2 => 'No photo posts yet.',
                    _ => 'No posts yet.',
                  },
                  style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                ),
              ),
            if (!_loadingPosts && _postsError == null)
              ..._visiblePosts.map(
                (post) => Padding(
                  padding: EdgeInsets.fromLTRB(
                      AppSpace.base, 0, AppSpace.base, AppSpace.base),
                  child: post.type == FeedPostType.text
                      ? _TextPostCard(
                          post: post,
                          onRepost: post.id == null ? null : () => _toggleRepost(post),
                          onReact: post.id == null ? null : () => _toggleReaction(post),
                          onComment: post.id == null ? null : () => _openComments(post),
                          onReport: post.id == null || post.authorId == _authService.currentUser?.id
                              ? null
                              : () => _reportPost(post),
                          onDelete: post.id != null && post.authorId == _authService.currentUser?.id
                              ? () => _deletePost(post)
                              : null,
                        )
                      : _VideoPostCard(
                          post: post,
                          onRepost: post.id == null ? null : () => _toggleRepost(post),
                          onReact: post.id == null ? null : () => _toggleReaction(post),
                          onComment: post.id == null ? null : () => _openComments(post),
                          onReport: post.id == null || post.authorId == _authService.currentUser?.id
                              ? null
                              : () => _reportPost(post),
                          onDelete: post.id != null && post.authorId == _authService.currentUser?.id
                              ? () => _deletePost(post)
                              : null,
                        ),
                ),
              ),
          ],
          ),
        ),
        Positioned(
          right: AppSpace.base,
          bottom: AppSpace.base,
          child: FloatingActionButton.extended(
            onPressed: () async {
              final posted = await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PostComposerScreen()),
              );
              if (posted == true) _loadPosts();
            },
            backgroundColor: AppColors.primary,
            icon: Icon(Icons.add),
            label: Text('New Post / Video', style: AppText.labelLg(color: AppColors.onPrimary)),
          ),
        ),
      ],
    );
  }

  void dismissPost(FeedPost post) {
    setState(() => _dismissedPosts.add(post.authorName));
  }

  List<FeedPost> get _visiblePosts => _posts.where((post) {
        if (_dismissedPosts.contains(post.authorName)) return false;
        return switch (_filter) {
          1 => post.type == FeedPostType.video,
          2 => post.imageUrl != null,
          _ => true,
        };
      }).toList();

  /// The soonest upcoming published event, linking to all [total] of them.
  /// This used to be a hardcoded "Richfield Annual Career Fair 2025, 18 - 20
  /// October 2025" with an RSVP button wired to () {}, under a row of
  /// "stories" from people who don't exist, one of them marked LIVE.
  Widget _eventBanner(Map<String, dynamic> event, {required int total}) {
    final date = DateTime.tryParse(event['event_date'] as String? ?? '')?.toLocal();
    final location = (event['location'] as String?)?.trim() ?? '';
    final description = (event['description'] as String?)?.trim() ?? '';
    return Container(
      padding: EdgeInsets.all(AppSpace.base),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Pill(
                text: 'UPCOMING EVENT',
                background: AppColors.tertiaryFixed,
                foreground: AppColors.onTertiaryContainer,
                icon: Icons.event_outlined,
              ),
              Spacer(),
              IconButton(
                tooltip: 'Hide event',
                onPressed: () => setState(() => _eventDismissed = true),
                icon: Icon(Icons.close, color: Colors.white70, size: 18),
              ),
            ],
          ),
          Text(event['title'] as String? ?? '', style: AppText.headlineSm(color: Colors.white)),
          if (description.isNotEmpty) ...[
            SizedBox(height: 4),
            Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppText.bodySm(color: Colors.white.withOpacity(0.85)),
            ),
          ],
          if (date != null || location.isNotEmpty) ...[
            SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.md,
              runSpacing: AppSpace.xs,
              children: [
                if (date != null) _bannerDetail(Icons.calendar_today_outlined, eventDateLabel(date)),
                if (location.isNotEmpty) _bannerDetail(Icons.location_on_outlined, location),
              ],
            ),
          ],
          SizedBox(height: AppSpace.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => EventsScreen()),
              ),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
              iconAlignment: IconAlignment.end,
              icon: Icon(Icons.arrow_forward, size: 16),
              label: Text(total > 1 ? 'See all $total upcoming events' : 'See all events'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bannerDetail(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          SizedBox(width: 4),
          Flexible(child: Text(text, style: AppText.bodySm(color: Colors.white70))),
        ],
      );
}

class _TextPostCard extends StatelessWidget {
  final FeedPost post;
  final VoidCallback? onRepost;
  final VoidCallback? onReact;
  final VoidCallback? onComment;
  final VoidCallback? onReport;
  final VoidCallback? onDelete;
  _TextPostCard({required this.post, this.onRepost, this.onReact, this.onComment, this.onReport, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return RoundedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _postAuthorRow(post, onReport: onReport, onDelete: onDelete),
          SizedBox(height: AppSpace.sm),
          if (post.body.isNotEmpty) Text(post.body, style: AppText.bodyMd()),
          if (post.imageUrl != null) ...[
            SizedBox(height: AppSpace.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Image.network(
                post.imageUrl!,
                width: double.infinity,
                fit: BoxFit.cover,
                // A dead CDN link must not blow up the whole feed list.
                errorBuilder: (_, __, ___) => Container(
                  height: 160,
                  color: AppColors.surfaceContainerHigh,
                  alignment: Alignment.center,
                  child: Icon(Icons.broken_image_outlined,
                      color: AppColors.onSurfaceVariant),
                ),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    height: 160,
                    color: AppColors.surfaceContainerLow,
                    alignment: Alignment.center,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                },
              ),
            ),
          ],
          SizedBox(height: AppSpace.sm),
          _engagementRow(post, onReact: onReact, onComment: onComment, onRepost: onRepost),
        ],
      ),
    );
  }
}

/// A post with a video attached. There is no in-app player yet, so this no
/// longer draws a play button that doesn't play, or a "1.4k Plays" count that
/// was really the repost total divided by 1000.
class _VideoPostCard extends StatelessWidget {
  final FeedPost post;
  final VoidCallback? onRepost;
  final VoidCallback? onReact;
  final VoidCallback? onComment;
  final VoidCallback? onReport;
  final VoidCallback? onDelete;
  _VideoPostCard({required this.post, this.onRepost, this.onReact, this.onComment, this.onReport, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return RoundedCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(AppSpace.base),
            child: _postAuthorRow(post, onReport: onReport, onDelete: onDelete),
          ),
          if (post.body.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpace.base),
              child: Text(post.body, style: AppText.bodyMd()),
            ),
          SizedBox(height: AppSpace.sm),
          AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.inverseSurface, Color(0xFF3B2A2E)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Center(
                    child: Icon(Icons.videocam_outlined, color: Colors.white24, size: 64),
                  ),
                ),
                if (post.videoLabel != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Pill(
                      text: post.videoLabel!,
                      background: Colors.black.withOpacity(0.55),
                      foreground: Colors.white,
                      icon: Icons.videocam_outlined,
                    ),
                  ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Row(
                    children: [
                      Icon(Icons.fiber_manual_record, color: AppColors.primary, size: 10),
                      SizedBox(width: 4),
                      Text('Career Reel', style: AppText.labelBadge(color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(AppSpace.base),
            child: _engagementRow(post, onReact: onReact, onComment: onComment, onRepost: onRepost),
          ),
        ],
      ),
    );
  }
}

class PostComposerScreen extends StatefulWidget {
  PostComposerScreen({super.key});

  @override
  State<PostComposerScreen> createState() => _PostComposerScreenState();
}

class _PostComposerScreenState extends State<PostComposerScreen> {
  bool _isVideo = false;
  bool _submitting = false;
  final _bodyController = TextEditingController();
  final _authService = AuthService(Supabase.instance.client);
  final _feedService = FeedService(Supabase.instance.client);
  final _mediaService = MediaService(Supabase.instance.client);

  /// Replaces the old `bool _hasAttachment`. That flag was set by
  /// `onPressed: () => setState(() => _hasAttachment = true)` and the card
  /// below it rendered the literal string 'portfolio-image.png' — the
  /// button never touched device storage, and there was no picker plugin
  /// in pubspec.yaml for it to call even if it had wanted to.
  PickedMedia? _attachment;
  String? _error;

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _pickAttachment() async {
    if (_isVideo) {
      // Video capture/compression is genuinely not built (rubric 8.4).
      // Say so plainly rather than pretending a file was attached.
      setState(() => _error = 'Video posting isn\'t available yet — post an image or text for now.');
      return;
    }
    try {
      final picked = await _mediaService.pickImage(source: ImageSource.gallery);
      // null = the user backed out of the gallery. Not an error.
      if (picked == null || !mounted) return;
      setState(() {
        _attachment = picked;
        _error = null;
      });
    } on MediaException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AuthErrorMapper.fromAny(e));
    }
  }

  Future<void> _submit() async {
    final body = _bodyController.text.trim();

    // Every one of these guards used to be a bare `return`, so tapping
    // Publish with an empty body — or with an expired session — did
    // nothing at all: no message, no spinner, no error. That silent no-op
    // is what got reported as 'student posts aren\'t reaching Supabase'.
    if (body.isEmpty && _attachment == null) {
      setState(() => _error = 'Write something or attach an image before posting.');
      return;
    }
    if (_isVideo) {
      setState(() => _error = 'Video posting isn\'t available yet — post an image or text for now.');
      return;
    }

    final authorId = _authService.currentUser?.id;
    if (authorId == null) {
      setState(() => _error = 'Your session has expired. Sign in again to post.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      // Upload first, then insert. If storage fails we must not leave a
      // posts row pointing at an object that was never written.
      String? imagePath;
      if (_attachment != null) {
        imagePath = await _mediaService.uploadPostImage(
          userId: authorId,
          media: _attachment!,
        );
      }

      await _feedService.createPost(
        authorId: authorId,
        body: body,
        imagePath: imagePath,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Posted'), duration: Duration(seconds: 1)),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = AuthErrorMapper.fromAny(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isVideo ? 'Create Video' : 'Create Post')),
      body: ListView(
        padding: EdgeInsets.all(AppSpace.base),
        children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text('Post'), icon: Icon(Icons.edit_outlined)),
              ButtonSegment(value: true, label: Text('Video'), icon: Icon(Icons.videocam_outlined)),
            ],
            selected: {_isVideo},
            onSelectionChanged: (value) => setState(() {
              _isVideo = value.first;
              _error = null;
            }),
          ),
          SizedBox(height: AppSpace.base),
          TextField(
            controller: _bodyController,
            minLines: 6,
            maxLines: 10,
            decoration: InputDecoration(
              hintText: _isVideo ? 'Tell your career story...' : 'Share a professional update...',
              filled: true,
              fillColor: AppColors.surfaceContainerLow,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide.none),
            ),
          ),
          SizedBox(height: AppSpace.md),
          OutlinedButton.icon(
            onPressed: _submitting ? null : _pickAttachment,
            icon: Icon(_isVideo ? Icons.video_library_outlined : Icons.image_outlined),
            label: Text(_attachment != null ? 'Change image' : 'Add image from device'),
          ),
          if (_attachment != null) ...[
            SizedBox(height: AppSpace.sm),
            RoundedCard(
              child: Row(
                children: [
                  // A real preview of the real file, not an icon next to a
                  // hardcoded filename.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Image.file(
                      _attachment!.file,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 56,
                        height: 56,
                        color: AppColors.surfaceContainerHigh,
                        child: Icon(Icons.broken_image_outlined,
                            color: AppColors.onSurfaceVariant),
                      ),
                    ),
                  ),
                  SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_attachment!.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.labelMd()),
                        Text(_attachment!.readableSize,
                            style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove image',
                    onPressed: _submitting ? null : () => setState(() => _attachment = null),
                    icon: Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            SizedBox(height: AppSpace.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 16, color: AppColors.error),
                SizedBox(width: 6),
                Expanded(child: Text(_error!, style: AppText.bodySm(color: AppColors.error))),
              ],
            ),
          ],
          SizedBox(height: AppSpace.xl),
          ElevatedButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.onPrimary),
                  )
                : Icon(Icons.send_outlined),
            label: Text(_submitting
                ? 'Publishing...'
                : (_isVideo ? 'Submit Video' : 'Publish Post')),
          ),
        ],
      ),
    );
  }
}

class StudentAnalyticsScreen extends StatefulWidget {
  StudentAnalyticsScreen({super.key});

  @override
  State<StudentAnalyticsScreen> createState() => _StudentAnalyticsScreenState();
}

class _StudentAnalyticsScreenState extends State<StudentAnalyticsScreen> {
  final _service = StudentAnalyticsService(Supabase.instance.client);
  StudentAnalytics? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await _service.load();
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = AuthErrorMapper.fromAny(e));
    }
  }

  String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(title: Text('Student Analytics')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.all(AppSpace.base),
          children: [
            Text('Your career signal', style: AppText.headlineLg()),
            Text('How employers and your network find and engage with your profile.',
                style: AppText.bodyMd(color: AppColors.onSurfaceVariant)),
            SizedBox(height: AppSpace.base),
            if (_error != null) ...[
              Text(_error!, style: AppText.bodySm(color: AppColors.error)),
              TextButton(onPressed: _load, child: Text('Try again')),
            ] else if (data == null)
              Padding(
                padding: EdgeInsets.all(AppSpace.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              ..._content(data),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(StudentAnalytics data) {
    final completeness = data.myCompleteness;
    final muted = AppText.bodySm(color: AppColors.onSurfaceVariant);
    return [
      _metricGrid([
        ['${data.totalProfileViews}', 'Profile views (${data.days}d)', Icons.visibility_outlined],
        ['${data.newConnections}', 'New connections (${data.days}d)', Icons.hub_outlined],
        ['${data.reactions + data.comments}', 'Reactions & comments', Icons.favorite_border],
        [completeness == null ? '—' : '${completeness.round()}%', 'Profile completeness', Icons.trending_up],
      ]),
      SizedBox(height: AppSpace.base),
      RoundedCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Profile views, last ${data.days} days', style: AppText.labelLg()),
            SizedBox(height: AppSpace.sm),
            if (data.totalProfileViews == 0)
              Text(
                'Nobody has opened your profile in this period yet. Views from the Network tab and member profiles show up here.',
                style: muted,
              )
            else ...[
              _DailyBars(values: data.dailyProfileViews, height: 100),
              SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text('${data.days} days ago', style: muted), Text('Today', style: muted)],
              ),
            ],
          ],
        ),
      ),
      SizedBox(height: AppSpace.sm),
      RoundedCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your skills businesses search for', style: AppText.labelLg()),
            if (data.searchedSkills.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: AppSpace.sm),
                child: Text('No business has searched for any of your listed skills yet.', style: muted),
              )
            else
              ..._searchedSkillRows(data.searchedSkills),
          ],
        ),
      ),
      SizedBox(height: AppSpace.sm),
      RoundedCard(
        child: Row(
          children: [
            Icon(Icons.groups_outlined, color: AppColors.secondary),
            SizedBox(width: AppSpace.sm),
            Expanded(child: Text(_programmeComparison(data), style: AppText.bodyMd())),
          ],
        ),
      ),
      SizedBox(height: AppSpace.sm),
      Text(
        'You have ${_plural(data.posts, 'post')}, with ${_plural(data.reactions, 'reaction')} and ${_plural(data.comments, 'comment')}.',
        style: muted,
      ),
    ];
  }

  Iterable<Widget> _searchedSkillRows(List<MapEntry<String, int>> skills) {
    final most = skills.fold<int>(0, (peak, e) => e.value > peak ? e.value : peak);
    return skills.map((e) => Padding(
          padding: EdgeInsets.only(top: AppSpace.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(e.key, style: AppText.bodySm())),
                  Text(e.value == 1 ? '1 search' : '${e.value} searches', style: AppText.labelMd()),
                ],
              ),
              SizedBox(height: 4),
              LinearProgressIndicator(
                value: most == 0 ? 0 : e.value / most,
                color: AppColors.secondary,
                backgroundColor: AppColors.surfaceContainerHigh,
              ),
            ],
          ),
        ));
  }

  String _programmeComparison(StudentAnalytics data) {
    final mine = data.myCompleteness;
    final average = data.programmeAverage;
    if (mine == null || average == null) {
      return 'Add your programme under Education on your Portfolio to compare your profile with others in your programme.';
    }
    final diff = (mine - average).round();
    final relation = diff > 0
        ? '$diff points above'
        : diff < 0
            ? '${-diff} points below'
            : 'level with';
    return 'Your profile is ${mine.round()}% complete, $relation the ${average.round()}% average in your programme.';
  }
}

/// Bars for a zero-filled daily series. Plain widgets rather than a
/// CustomPainter so they repaint with the theme on a dark-mode toggle.
class _DailyBars extends StatelessWidget {
  _DailyBars({required this.values, required this.height});

  final List<int> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    final peak = values.fold<int>(0, (a, b) => b > a ? b : a);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final v in values)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 1),
                child: Container(
                  height: v == 0 || peak == 0 ? 2 : (height * v / peak).clamp(4.0, height),
                  decoration: BoxDecoration(
                    color: v == 0 ? AppColors.surfaceContainerHigh : AppColors.primary,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Asks first, then deletes. Returns true only once the post is gone, so the
/// caller can drop it from its list; a failure is shown here. Keshav's QA
/// pass (2026-09-11) found the ••• menu only ever offered Report, and hid
/// even that on your own posts, so an author had no way to remove a post.
Future<bool> _confirmAndDeletePost(BuildContext context, FeedPost post) async {
  final postId = post.id;
  if (postId == null) return false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete this post?'),
      content: Text('It will be removed from the feed with its likes, comments and reposts. This can\'t be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await FeedService(Supabase.instance.client).deletePost(postId);
    messenger.showSnackBar(SnackBar(content: Text('Post deleted.')));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(AuthErrorMapper.fromAny(e))));
    return false;
  }
}

/// [onDelete] is passed for the viewer's own posts and [onReport] for
/// everyone else's, so the ••• menu offers whichever applies.
Widget _postAuthorRow(FeedPost post, {VoidCallback? onReport, VoidCallback? onDelete}) {
  return Row(
    children: [
      InitialsAvatar(initials: post.authorName.split(' ').map((e) => e[0]).take(2).join()),
      SizedBox(width: AppSpace.sm),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    post.authorName,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.labelLg(),
                  ),
                ),
                if (post.verified) ...[
                  SizedBox(width: 4),
                  Icon(Icons.verified, size: 14, color: AppColors.tertiaryFixedDim),
                ],
              ],
            ),
            Text(post.authorRole,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
          ],
        ),
      ),
      SizedBox(width: AppSpace.sm),
      Flexible(
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            post.timeAgo,
            overflow: TextOverflow.ellipsis,
            style: AppText.bodySm(color: AppColors.onSurfaceVariant),
          ),
        ),
      ),
      if (onReport != null || onDelete != null)
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: Icon(Icons.more_horiz, color: AppColors.onSurfaceVariant),
          onSelected: (value) {
            if (value == 'delete') onDelete?.call();
            if (value == 'report') onReport?.call();
          },
          itemBuilder: (_) => [
            if (onDelete != null)
              PopupMenuItem(
                value: 'delete',
                child: Text('Delete post', style: TextStyle(color: AppColors.error)),
              ),
            if (onReport != null) PopupMenuItem(value: 'report', child: Text('Report post')),
          ],
        ),
    ],
  );
}

/// Like / Comment / Repost / Share for a feed card. Share has nothing behind
/// it yet, so it stays disabled.
Widget _engagementRow(
  FeedPost post, {
  VoidCallback? onReact,
  VoidCallback? onComment,
  VoidCallback? onRepost,
}) {
  return _reactionRow(
    aLabel: '${post.reactionCountA} ${post.reactionCountA == 1 ? 'Like' : 'Likes'}',
    aIcon: Icons.thumb_up_alt_outlined,
    bLabel: '${post.reactionCountB} ${post.reactionCountB == 1 ? 'Comment' : 'Comments'}',
    bIcon: Icons.mode_comment_outlined,
    cLabel: '${post.reactionCountC} ${post.reactionCountC == 1 ? 'Repost' : 'Reposts'}',
    cIcon: Icons.repeat,
    actions: ['Like', 'Comment', 'Repost', 'Share'],
    actionIcons: [
      post.isReacted ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
      Icons.mode_comment_outlined,
      Icons.repeat,
      Icons.share_outlined,
    ],
    actionHandlers: [onReact, onComment, onRepost, null],
    activeActions: {if (post.isReacted) 0, if (post.isReposted) 2},
  );
}

/// Engagement row.
///
/// Every button here used to be built with a literal `onPressed: () {}` —
/// all four actions (Endorse / Comment / Repost / Share) on every card in
/// the feed were no-ops that rendered as enabled and did nothing on tap.
/// Handlers are now passed in per action; an action with a null handler
/// renders visibly disabled instead of silently swallowing the tap.
Widget _reactionRow({
  required String aLabel,
  required IconData aIcon,
  required String bLabel,
  required IconData bIcon,
  required String cLabel,
  required IconData cIcon,
  required List<String> actions,
  required List<IconData> actionIcons,
  List<VoidCallback?>? actionHandlers,
  Set<int> activeActions = const {},
}) {
  return Column(
    children: [
      Wrap(
        spacing: AppSpace.md,
        runSpacing: AppSpace.xs,
        children: [
          _metricLabel(aIcon, aLabel),
          _metricLabel(bIcon, bLabel),
          _metricLabel(cIcon, cLabel),
        ],
      ),
      Divider(height: AppSpace.md, color: AppColors.outlineVariant),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        children: List.generate(actions.length, (i) {
          final handler =
              (actionHandlers != null && i < actionHandlers.length) ? actionHandlers[i] : null;
          final active = activeActions.contains(i);
          final tint = active
              ? AppColors.primary
              : (handler == null ? AppColors.outline : AppColors.onSurfaceVariant);
          return TextButton.icon(
            onPressed: handler,
            icon: Icon(actionIcons[i], size: 16, color: tint),
            label: Text(actions[i], style: AppText.labelMd(color: tint)),
          );
        }),
      ),
    ],
  );
}

Widget _metricLabel(IconData icon, String label) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: AppColors.onSurfaceVariant),
      SizedBox(width: 4),
      Text(label, style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
    ],
  );
}

// =====================================================================
// SECTION 9 — JOBS SCREEN
// (No Stitch export existed for this tab — built to match the design
// system so the bottom nav has four real destinations, not placeholders.)
// =====================================================================

class JobsScreen extends StatefulWidget {
  JobsScreen({super.key});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  final _authService = AuthService(Supabase.instance.client);
  final _jobsService = JobsService(Supabase.instance.client);
  final _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _all = [];
  String _typeFilter = 'All';
  String _query = '';
  String _role = '';

  /// recommend_opportunities() rows keyed by opportunity id, and their
  /// ranked order. The header used to say "SMART-MATCHED FOR YOU" over a
  /// plain list of every approved listing; nothing was matched.
  Map<String, Map<String, dynamic>> _matches = {};
  List<String> _recommendedIds = [];
  String? _matchError;

  static const _typeOptions = ['All', 'internship', 'learnership', 'part_time', 'graduate_vacancy'];
  static const _typeLabels = {
    'All': 'All',
    'internship': 'Internship',
    'learnership': 'Learnership',
    'part_time': 'Part-time',
    'graduate_vacancy': 'Graduate Vacancy',
  };

  bool get _hasCareerProfile => _role == 'student' || _role == 'alumni';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Matching runs alongside the listing query, and its failure is kept
      // rather than thrown: the full list is still useful without it.
      final matching = _jobsService
          .fetchRecommendations()
          .then<Object>((rows) => rows, onError: (Object e) => e);
      final results = await Future.wait<Object?>([
        _jobsService.fetchApprovedOpportunities(),
        _authService.fetchOwnProfile(),
        matching,
      ]);

      final profile = results[1] as Map<String, dynamic>?;
      final matched = results[2];
      final recommendations =
          matched is List ? List<Map<String, dynamic>>.from(matched) : <Map<String, dynamic>>[];

      if (!mounted) return;
      setState(() {
        _all = results[0] as List<Map<String, dynamic>>;
        _role = profile?['role'] as String? ?? '';
        _matches = {for (final r in recommendations) r['opportunity_id'] as String: r};
        _recommendedIds = [for (final r in recommendations) r['opportunity_id'] as String];
        _matchError = matched is List ? null : AuthErrorMapper.fromAny(matched!);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AuthErrorMapper.fromAny(e);
        _loading = false;
      });
    }
  }

  bool _passesFilters(Map<String, dynamic> o) {
    final matchesType = _typeFilter == 'All' || o['opportunity_type'] == _typeFilter;
    final title = (o['title'] as String? ?? '').toLowerCase();
    final matchesQuery = _query.isEmpty || title.contains(_query.toLowerCase());
    return matchesType && matchesQuery;
  }

  List<Map<String, dynamic>> get _filtered => _all.where(_passesFilters).toList();

  /// Recommended listings in ranked order, as full rows (the RPC returns
  /// only ids and scores), under the same search and type filter.
  List<Map<String, dynamic>> get _recommended {
    final byId = {for (final o in _all) o['id'] as String: o};
    return [
      for (final id in _recommendedIds)
        if (byId[id] != null && _passesFilters(byId[id]!)) byId[id]!,
    ];
  }

  Future<void> _apply(Map<String, dynamic> job) async {
    final studentId = _authService.currentUser?.id;
    if (studentId == null) return;
    try {
      await _jobsService.apply(opportunityId: job['id'] as String, studentId: studentId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Applied to ${job['title']}.')));
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final message = e.code == '23505'
          ? "You've already applied to this role."
          : AuthErrorMapper.fromPostgrestException(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthErrorMapper.fromAny(e))));
    }
  }

  void _showDetails(Map<String, dynamic> job) {
    final skills = (job['required_skills'] as List?)?.cast<String>() ?? [];
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(job['title'] as String? ?? 'Opportunity'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(job['description'] as String? ?? ''),
              if (skills.isNotEmpty) ...[
                SizedBox(height: AppSpace.sm),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: skills
                      .map((s) => Pill(
                            text: s,
                            background: AppColors.surfaceContainerHigh,
                            foreground: AppColors.onSurfaceVariant,
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppText.bodySm(color: AppColors.onSurfaceVariant);
    final horizontal = EdgeInsets.symmetric(horizontal: AppSpace.base);
    final recommended = _recommended;
    final filtered = _filtered;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.only(bottom: 24),
        children: [
          RichfieldHeader(
            title: 'Opportunities',
            subtitle: 'INTERNSHIPS • LEARNERSHIPS • GRADUATE ROLES',
            onAvatarTap: () => _openAccountMenu(context, _authService),
          ),
          Padding(
            padding: horizontal,
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Search internships, learnerships, graduate roles…',
                filled: true,
                fillColor: AppColors.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(height: AppSpace.sm),
          Padding(
            padding: horizontal,
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _typeOptions.length,
                separatorBuilder: (_, __) => SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final opt = _typeOptions[i];
                  return ChoiceChip(
                    label: Text(_typeLabels[opt]!),
                    selected: _typeFilter == opt,
                    onSelected: (_) => setState(() => _typeFilter = opt),
                  );
                },
              ),
            ),
          ),
          SizedBox(height: AppSpace.base),
          if (_loading)
            Padding(
              padding: EdgeInsets.all(AppSpace.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (!_loading && _error != null)
            Padding(
              padding: horizontal,
              child: Text(_error!, style: AppText.bodySm(color: AppColors.error)),
            ),
          if (!_loading && _error == null) ...[
            if (_hasCareerProfile) ...[
              Padding(padding: horizontal, child: SectionHeader(title: 'Recommended for you')),
              Padding(
                padding: horizontal,
                child: Text(
                  "Ranked by how many of a listing's required skills are on your profile, and whether it's open to your programme.",
                  style: muted,
                ),
              ),
              SizedBox(height: AppSpace.sm),
              if (_matchError != null)
                Padding(
                  padding: horizontal,
                  child: Text(_matchError!, style: AppText.bodySm(color: AppColors.error)),
                )
              else if (recommended.isEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(AppSpace.base, 0, AppSpace.base, AppSpace.sm),
                  child: RoundedCard(
                    child: Text(
                      _recommendedIds.isEmpty
                          ? 'No matches yet. Add skills and your programme on your Portfolio, and listings that ask for them will appear here.'
                          : 'None of your recommended listings match this search or filter.',
                      style: muted,
                    ),
                  ),
                )
              else
                ...recommended.map(_jobCard),
              SizedBox(height: AppSpace.sm),
            ],
            Padding(padding: horizontal, child: SectionHeader(title: 'All opportunities')),
            if (filtered.isEmpty)
              Padding(
                padding: horizontal,
                child: Text('No opportunities match right now.', style: muted),
              )
            else
              ...filtered.map(_jobCard),
          ],
        ],
      ),
    );
  }

  Widget _jobCard(Map<String, dynamic> job) {
    final business = job['profiles']?['business_profiles'] as Map<String, dynamic>?;
    final company = business?['company_name'] as String? ?? 'Unknown company';
    final location = business?['location'] as String? ?? '';
    final skills = (job['required_skills'] as List?)?.cast<String>() ?? [];
    final match = _matches[job['id']];
    final matchedSkills = {
      for (final s in (match?['matched_skills'] as List?)?.cast<String>() ?? const <String>[])
        s.trim().toLowerCase(),
    };
    final programmeMatch = match?['programme_match'] == true;
    final score = (match?['match_score'] as num?)?.toDouble();

    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.base, 0, AppSpace.base, AppSpace.sm),
      child: RoundedCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(Icons.business_center_outlined, color: AppColors.secondary),
                ),
                SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(job['title'] as String? ?? '', style: AppText.labelLg()),
                      Text(
                        '$company${location.isEmpty ? '' : ' • $location'}',
                        style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: AppSpace.sm),
                Pill(
                  text: _typeLabels[job['opportunity_type']] ?? job['opportunity_type'] as String? ?? '',
                  background: AppColors.tertiaryContainer.withOpacity(0.3),
                  foreground: AppColors.tertiary,
                ),
              ],
            ),
            if (match != null) ...[
              SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (score != null)
                    Pill(
                      text: '${(score * 100).round()}% MATCH',
                      icon: Icons.auto_awesome,
                      background: AppColors.successGreenBg,
                      foreground: AppColors.successGreen,
                    ),
                  if (programmeMatch)
                    Pill(
                      text: 'YOUR PROGRAMME',
                      icon: Icons.school_outlined,
                      background: AppColors.secondaryContainer,
                      foreground: AppColors.onSecondaryContainer,
                    ),
                ],
              ),
            ],
            SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in skills)
                  matchedSkills.contains(s.trim().toLowerCase())
                      ? Pill(
                          text: s,
                          icon: Icons.check,
                          background: AppColors.successGreenBg,
                          foreground: AppColors.successGreen,
                        )
                      : Pill(
                          text: s,
                          background: AppColors.surfaceContainerHigh,
                          foreground: AppColors.onSurfaceVariant,
                        ),
              ],
            ),
            SizedBox(height: AppSpace.sm),
            Row(
              children: [
                SecondaryButton(
                  label: 'View Details',
                  icon: Icons.visibility_outlined,
                  onPressed: () => _showDetails(job),
                ),
                SizedBox(width: AppSpace.sm),
                Expanded(
                  child: PrimaryButton(
                    label: 'Apply',
                    icon: Icons.send_outlined,
                    fullWidth: true,
                    onPressed: () => _apply(job),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// SECTION 10 — NETWORK SCREEN: now screens/network_screen.dart (real
// connections, requests, suggestions and search).
// =====================================================================

// =====================================================================
// SECTION 11 — PORTFOLIO SCREEN (most detailed — 1:1 with code.html)
// =====================================================================

class PortfolioScreen extends StatefulWidget {
  PortfolioScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

/// One card in the activity list: a post the member wrote, or one they
/// reposted (credited to its original author, dated by the repost).
class _ActivityItem {
  _ActivityItem({required this.post, required this.at, required this.isRepost});

  final FeedPost post;
  final DateTime at;
  final bool isRepost;
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  Map<String, dynamic>? _profile;

  PortfolioData _portfolio = PortfolioData();
  bool _loadingPortfolio = true;
  String? _portfolioError;

  /// profiles.cv_path / cv_uploaded_at (migration 038). Read separately
  /// from the profile row; see ProfileService.fetchCvStatus.
  ({String? path, DateTime? uploadedAt})? _cvStatus;
  bool _cvBusy = false;

  List<_ActivityItem> _activity = [];
  bool _loadingActivity = true;
  String? _activityError;

  final _profileService = ProfileService(Supabase.instance.client);
  final _mediaService = MediaService(Supabase.instance.client);
  final _portfolioService = PortfolioService(Supabase.instance.client);
  final _feedService = FeedService(Supabase.instance.client);

  String? get _userId => widget.authService.currentUser?.id;
  String get _role => _profile?['role'] as String? ?? '';

  /// Students and alumni keep a career portfolio. A business or staff
  /// account's tab is its header, links and activity — it used to show them
  /// the same invented student credentials as everyone else.
  bool get _hasCareerProfile => _role == 'student' || _role == 'alumni';

  TextStyle get _muted => AppText.bodySm(color: AppColors.onSurfaceVariant);

  @override
  void initState() {
    super.initState();
    _reloadProfile();
    _loadPortfolio();
    _loadCvStatus();
    _loadActivity();
  }

  Future<void> _refresh() async {
    await Future.wait([_reloadProfile(), _loadPortfolio(), _loadCvStatus(), _loadActivity()]);
  }

  Future<void> _loadCvStatus() async {
    final userId = _userId;
    if (userId == null) return;
    try {
      final status = await _profileService.fetchCvStatus(userId);
      if (!mounted) return;
      setState(() => _cvStatus = status);
    } catch (_) {
      // The card falls back to "no CV on file"; nothing else depends on it.
    }
  }

  Future<void> _openCv() async {
    final path = _cvStatus?.path;
    if (path == null) return;
    setState(() => _cvBusy = true);
    try {
      final url = await _mediaService.cvSignedUrl(path);
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No app on this device could open the PDF.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthErrorMapper.fromAny(e))));
    } finally {
      if (mounted) setState(() => _cvBusy = false);
    }
  }

  Future<void> _removeCv() async {
    final userId = _userId;
    final path = _cvStatus?.path;
    if (userId == null || path == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Remove your CV?'),
        content: Text('The PDF is deleted from your profile. Your extracted details stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text('Keep it')),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text('Remove', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cvBusy = true);
    try {
      // Pointer first, then the object: a row pointing at a missing file is
      // the worse of the two failure modes.
      await _profileService.setCvPath(userId: userId, path: null);
      await _mediaService.removeCv(path);
      if (!mounted) return;
      setState(() => _cvStatus = (path: null, uploadedAt: null));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthErrorMapper.fromAny(e))));
    } finally {
      if (mounted) setState(() => _cvBusy = false);
    }
  }

  Future<void> _loadPortfolio() async {
    final userId = _userId;
    if (userId == null) return;
    try {
      final data = await _portfolioService.load(userId);
      if (!mounted) return;
      setState(() {
        _portfolio = data;
        _portfolioError = null;
        _loadingPortfolio = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _portfolioError = AuthErrorMapper.fromAny(e);
        _loadingPortfolio = false;
      });
    }
  }

  Future<void> _loadActivity() async {
    final userId = _userId;
    if (userId == null) return;
    try {
      final results = await Future.wait<Object>([
        _feedService.fetchPostsByAuthor(userId),
        _feedService.fetchRepostsBy(userId),
        _feedService.fetchMyReactedPostIds(userId),
      ]);
      final ownPosts = results[0] as List<Map<String, dynamic>>;
      final reposts = results[1] as List<Map<String, dynamic>>;
      final reactedIds = results[2] as Set<String>;
      final repostedIds = {
        for (final r in reposts)
          if (r['posts'] is Map) (r['posts'] as Map)['id'] as String,
      };
      DateTime when(Object? iso) => DateTime.tryParse(iso as String? ?? '') ?? DateTime.now();

      final items = <_ActivityItem>[
        for (final row in ownPosts)
          _ActivityItem(
            post: _feedPostFromRow(
              row,
              repostedIds: repostedIds,
              reactedIds: reactedIds,
              mediaService: _mediaService,
            ),
            at: when(row['created_at']),
            isRepost: false,
          ),
        for (final r in reposts)
          if (r['posts'] is Map)
            _ActivityItem(
              post: _feedPostFromRow(
                Map<String, dynamic>.from(r['posts'] as Map),
                repostedIds: repostedIds,
                reactedIds: reactedIds,
                mediaService: _mediaService,
              ),
              at: when(r['created_at']),
              isRepost: true,
            ),
      ]..sort((a, b) => b.at.compareTo(a.at));

      if (!mounted) return;
      setState(() {
        _activity = items;
        _activityError = null;
        _loadingActivity = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _activityError = AuthErrorMapper.fromAny(e);
        _loadingActivity = false;
      });
    }
  }

  Future<void> _deletePost(_ActivityItem item) async {
    if (!await _confirmAndDeletePost(context, item.post)) return;
    if (!mounted) return;
    // Your own post can also be in this list a second time, as your repost.
    setState(() => _activity = _activity.where((a) => a.post.id != item.post.id).toList());
  }

  Future<void> _toggleRepost(FeedPost post) async {
    final postId = post.id;
    final userId = _userId;
    if (postId == null || userId == null) return;
    try {
      await _feedService.toggleRepost(
        postId: postId,
        userId: userId,
        currentlyReposted: post.isReposted,
      );
      await _loadActivity();
    } catch (e) {
      _snack(AuthErrorMapper.fromAny(e));
    }
  }

  Future<void> _toggleReaction(FeedPost post) async {
    final postId = post.id;
    final userId = _userId;
    if (postId == null || userId == null) return;
    try {
      await _feedService.toggleReaction(postId: postId, userId: userId, currentlyReacted: post.isReacted);
      await _loadActivity();
    } catch (e) {
      _snack(AuthErrorMapper.fromAny(e));
    }
  }

  void _openComments(FeedPost post) {
    final postId = post.id;
    if (postId == null) return;
    showCommentsSheet(context, postId: postId, onCountChanged: (_) {}).then((_) {
      if (mounted) _loadActivity();
    });
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _addEntry(PortfolioSection section) async {
    final userId = _userId;
    if (userId == null) return;
    final saved = await showPortfolioEntrySheet(
      context,
      section: section,
      onSave: (values) => _portfolioService.add(section, userId: userId, values: values),
    );
    if (saved) await _loadPortfolio();
  }

  Future<void> _removeEntry(PortfolioSection section, Map<String, dynamic> row) async {
    final name = (row['title'] ?? row['programme'] ?? row['role_title'] ?? 'this entry').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove "$name"?'),
        content: Text('It will no longer appear on your portfolio or to anyone viewing your profile.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _portfolioService.remove(section, row['id'] as String);
      await _loadPortfolio();
    } catch (e) {
      _snack(AuthErrorMapper.fromAny(e));
    }
  }

  /// Opens the edit form and adopts whatever row comes back, so the header
  /// repaints from the database's version of the truth rather than from
  /// what the form hoped it wrote.
  Future<void> _openEditProfile() async {
    final userId = widget.authService.currentUser?.id;
    final profile = _profile;
    if (userId == null || profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Still loading your profile — try again in a moment.')),
      );
      return;
    }

    final updated = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          userId: userId,
          profile: profile,
          profileService: _profileService,
          mediaService: _mediaService,
        ),
      ),
    );

    if (updated != null && mounted) setState(() => _profile = updated);
  }

  Future<void> _openCvImport() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CvImportScreen()));
    await Future.wait([_reloadProfile(), _loadPortfolio(), _loadCvStatus()]);
  }

  Future<void> _openLink(String? rawUrl, String label) async {
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      // Prompt the user to add one instead of doing nothing at all.
      await _openEditProfile();
      return;
    }
    final uri = Uri.tryParse(ProfileService.normalizeUrl(rawUrl));
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open your $label link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: EdgeInsets.only(bottom: 90),
            children: [
              RichfieldHeader(
                title: 'Portfolio',
                subtitle: 'RICHFIELD VERIFIED',
                extraAction: _hasCareerProfile
                    ? IconButton(
                        tooltip: 'Open student analytics',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => StudentAnalyticsScreen()),
                        ),
                        icon: Icon(Icons.analytics_outlined),
                      )
                    : null,
                onAvatarTap: () => _openAccountMenu(context, widget.authService),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpace.base),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _profileHeaderCard(),
                    SizedBox(height: AppSpace.base),
                    _statsCard(),
                    SizedBox(height: AppSpace.base),
                    _socialLinksRow(),
                    SizedBox(height: AppSpace.md),
                    Row(
                      children: [
                        SecondaryButton(
                          label: 'Edit Details',
                          icon: Icons.edit_outlined,
                          onPressed: _openEditProfile,
                        ),
                        if (_hasCareerProfile) ...[
                          SizedBox(width: AppSpace.sm),
                          SecondaryButton(
                            label: 'Import CV',
                            icon: Icons.upload_file_outlined,
                            onPressed: _openCvImport,
                          ),
                        ],
                      ],
                    ),
                    if (_portfolioError != null) ...[
                      SizedBox(height: AppSpace.md),
                      Text(_portfolioError!, style: AppText.bodySm(color: AppColors.error)),
                      TextButton(onPressed: _loadPortfolio, child: Text('Try again')),
                    ],
                    if (_hasCareerProfile && !_loadingPortfolio && _portfolioError == null)
                      ..._careerSections(),
                    SizedBox(height: AppSpace.lg),
                    _activitySection(),
                    SizedBox(height: AppSpace.xxl),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: AppSpace.base,
          bottom: AppSpace.base,
          child: FloatingActionButton(
            heroTag: 'career_ai_fab',
            backgroundColor: AppColors.primary,
            onPressed: () => _openCareerAiSheet(context),
            child: Icon(Icons.auto_awesome, color: Colors.white),
          ),
        ),
      ],
    );
  }

  /// The sheet doesn't navigate by itself — it pops with the screen the user
  /// picked and this pushes it, so Portfolio knows when they come back from
  /// the assistant or a CV import and can repaint from the database instead
  /// of showing the pre-import headline until the next restart.
  Future<void> _openCareerAiSheet(BuildContext context) async {
    final next = await showModalBottomSheet<Widget>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RichfieldCareerAiSheet(),
    );
    if (next == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => next));
    await Future.wait([_reloadProfile(), _loadPortfolio()]);
  }

  /// Uncached on purpose: AuthService.fetchOwnProfile() holds a 30-second
  /// cache for the router, which would hand back the row from before the edit.
  Future<void> _reloadProfile() async {
    final userId = widget.authService.currentUser?.id;
    if (userId == null) return;
    try {
      final fresh = await _profileService.fetchProfile(userId);
      if (mounted) setState(() => _profile = fresh);
    } catch (_) {
      // Keep what's on screen; a failed background refresh isn't worth an error.
    }
  }

  /// Says what the account is. It used to read 'VERIFIED STUDENT •
  /// @my.richfield.ac.za' on every account, businesses and staff included.
  String? _roleBadge() => switch (_role) {
        'student' => 'RICHFIELD STUDENT',
        'alumni' => 'RICHFIELD ALUMNI',
        'business' => 'BUSINESS PARTNER',
        'administrator' => 'RICHFIELD STAFF',
        _ => null,
      };

  String _educationLine() {
    if (_portfolio.education.isEmpty) return '';
    final e = _portfolio.education.first;
    final graduation = e['graduation_year'];
    return _joinParts([
      e['programme'],
      e['campus'],
      if (graduation != null) 'Class of $graduation',
    ]);
  }

  Widget _profileHeaderCard() {
    final firstName = _profile?['first_name'] as String? ?? '';
    final lastName = _profile?['last_name'] as String? ?? '';
    final fullName = ('$firstName $lastName').trim();
    final displayName = fullName.isEmpty ? 'Richfield Member' : fullName;
    final initials =
        (firstName.isNotEmpty ? firstName[0] : '') + (lastName.isNotEmpty ? lastName[0] : '');
    final headline = (_profile?['professional_headline'] as String?)?.trim() ?? '';
    final bio = (_profile?['bio'] as String?)?.trim() ?? '';
    final avatarPath = _profile?['avatar_path'] as String?;
    final badge = _roleBadge();
    final educationLine = _educationLine();

    return RoundedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The whole avatar is the tap target — the camera badge on its
              // own is below the minimum touch size.
              GestureDetector(
                onTap: _openEditProfile,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: AppColors.secondaryContainer,
                      backgroundImage: avatarPath == null || avatarPath.isEmpty
                          ? null
                          : NetworkImage(_mediaService.avatarUrl(avatarPath)),
                      child: avatarPath == null || avatarPath.isEmpty
                          ? Text(initials.isEmpty ? '?' : initials,
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onSecondaryContainer))
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.photo_camera_outlined,
                            size: 14, color: AppColors.onPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (badge != null)
                      Pill(
                        text: badge,
                        background: AppColors.successGreenBg,
                        foreground: AppColors.successGreen,
                        icon: Icons.badge_outlined,
                        fontSize: 9,
                      ),
                    SizedBox(height: 6),
                    Text(displayName, style: AppText.headlineMd()),
                    if (headline.isNotEmpty)
                      Text(headline, style: _muted)
                    else if (_profile != null)
                      GestureDetector(
                        onTap: _openEditProfile,
                        child: Text('Add a professional headline',
                            style: AppText.bodySm(color: AppColors.secondary)),
                      ),
                    if (educationLine.isNotEmpty) ...[
                      SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.school_outlined, size: 12, color: AppColors.primary),
                          SizedBox(width: 4),
                          Expanded(child: Text(educationLine, style: _muted)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (bio.isNotEmpty) ...[
            SizedBox(height: AppSpace.sm),
            Text(bio, style: _muted),
          ],
        ],
      ),
    );
  }

  /// Was '482' network, '18' endorsements, '94%' profile score and a 'Top 5%
  /// Cohort' pill, identical on every account. Profile strength uses the same
  /// ProfileContext as the Career AI sheet, so the two never disagree.
  Widget _statsCard() {
    Widget stat(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(value, style: AppText.headlineMd(color: AppColors.primary)),
              Text(label, textAlign: TextAlign.center, style: _muted),
            ],
          ),
        );

    final profile = _profile;
    final profileContext = profile == null || _loadingPortfolio
        ? null
        : ProfileContext(
            profile: profile,
            skills: _portfolio.skills,
            education: _portfolio.education,
            workExperience: _portfolio.experience,
            projects: _portfolio.projects,
            certifications: _portfolio.certifications,
          );
    final next = profileContext?.nextStep;

    return RoundedCard(
      child: Column(
        children: [
          Row(
            children: [
              stat(_loadingPortfolio ? '—' : '${_portfolio.connectionCount}', 'Connections'),
              stat(_loadingPortfolio ? '—' : '${_portfolio.endorsements.length}', 'Endorsements'),
              stat(
                profileContext == null ? '—' : '${(profileContext.completeness * 100).round()}%',
                'Profile strength',
              ),
            ],
          ),
          if (profileContext != null && _hasCareerProfile) ...[
            Divider(height: AppSpace.lg, color: AppColors.outlineVariant),
            InkWell(
              onTap: () => _openCareerAiSheet(context),
              child: Row(
                children: [
                  Icon(next == null ? Icons.verified_outlined : Icons.flag_outlined,
                      size: 14, color: AppColors.tertiary),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      next == null ? 'Every profile section is filled in' : 'Next step: ${next.label}',
                      style: _muted,
                    ),
                  ),
                  Pill(
                    text: 'CAREER AI',
                    icon: Icons.auto_awesome,
                    background: AppColors.tertiaryContainer.withOpacity(0.3),
                    foreground: AppColors.tertiary,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Was three hardcoded Text widgets — including the literal
  /// 'github.com/siphok', a name from the mock data that showed on every
  /// user's profile — with no tap target on any of them. Now reads the
  /// real profile columns added in migration 024 and opens them.
  Widget _socialLinksRow() {
    final profile = _profile;

    Widget link(IconData icon, String label, String? url) {
      final hasUrl = url != null && url.trim().isNotEmpty;
      final tint = hasUrl ? AppColors.secondary : AppColors.onSurfaceVariant;
      return Expanded(
        child: InkWell(
          onTap: () => _openLink(url, label),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(hasUrl ? icon : Icons.add_link, size: 14, color: tint),
                SizedBox(width: 4),
                Flexible(
                  child: Text(
                    hasUrl ? _prettyUrl(url) : 'Add $label',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodySm(color: tint),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return RoundedCard(
      padding: EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Row(
        children: [
          link(Icons.code, 'GitHub', profile?['github_url'] as String?),
          link(Icons.business_center_outlined, 'LinkedIn',
              profile?['linkedin_url'] as String?),
          link(Icons.language, 'Website', profile?['website_url'] as String?),
        ],
      ),
    );
  }

  /// 'https://github.com/reilisticdev' -> 'github.com/reilisticdev'.
  /// Keeps the row readable at three-across without truncating to noise.
  String _prettyUrl(String url) {
    final stripped = url
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'^www\.'), '');
    return stripped.endsWith('/')
        ? stripped.substring(0, stripped.length - 1)
        : stripped;
  }

  String _joinParts(List<Object?> parts) => parts
      .whereType<Object>()
      .map((p) => p.toString().trim())
      .where((p) => p.isNotEmpty)
      .join(' • ');

  String? _dateRange(Object? start, Object? end) {
    final from = monthYearLabel(start);
    final to = monthYearLabel(end);
    if (from == null && to == null) return null;
    return '${from ?? '?'} – ${to ?? 'Present'}';
  }

  String? _yearRange(Map<String, dynamic> row) {
    final start = row['enrolment_year'];
    final end = row['graduation_year'];
    if (start == null && end == null) return null;
    return '${start ?? '?'}–${end ?? 'present'}';
  }

  /// Every section below used to be MockData: an AWS certificate, two GitHub
  /// repos with star counts, 'SRC Technology Officer', endorsement counts
  /// under an 'Endorse Sipho' link and a lecturer's recommendation of
  /// "Sipho" — the same on every account, with no way to add real ones.
  List<Widget> _careerSections() {
    final p = _portfolio;
    return [
      SizedBox(height: AppSpace.xl),
      _cvEvidenceCard(),
      SizedBox(height: AppSpace.lg),
      _skillsSection(),
      _entrySection(
        section: PortfolioSection.experience,
        title: 'Experience',
        rows: p.experience,
        empty: 'Internships, part-time work and volunteering all count.',
        card: (row, onRemove) => _entryCard(
          icon: Icons.work_outline,
          title: row['title'] as String? ?? '',
          subtitle: _joinParts([row['organisation'], _dateRange(row['start_date'], row['end_date'])]),
          body: row['description'] as String?,
          onRemove: onRemove,
        ),
      ),
      _entrySection(
        section: PortfolioSection.education,
        title: 'Education',
        rows: p.education,
        empty: 'Add your programme so job matching and your programme comparison can use it.',
        card: (row, onRemove) => _entryCard(
          icon: Icons.school_outlined,
          title: row['programme'] as String? ?? '',
          subtitle: _joinParts([row['campus'], _yearRange(row)]),
          onRemove: onRemove,
        ),
      ),
      _entrySection(
        section: PortfolioSection.projects,
        title: 'Projects',
        rows: p.projects,
        empty: 'Coursework, hackathon and personal projects show recruiters what you can build.',
        card: (row, onRemove) {
          final source = (row['github_url'] as String?)?.trim() ?? '';
          final live = (row['live_url'] as String?)?.trim() ?? '';
          return _entryCard(
            icon: Icons.terminal,
            title: row['title'] as String? ?? '',
            body: row['description'] as String?,
            onRemove: onRemove,
            actions: [
              if (source.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _openLink(source, 'source code'),
                  icon: Icon(Icons.code, size: 16),
                  label: Text('Source'),
                ),
              if (live.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _openLink(live, 'live demo'),
                  icon: Icon(Icons.open_in_new, size: 16),
                  label: Text('Live demo'),
                ),
            ],
          );
        },
      ),
      _entrySection(
        section: PortfolioSection.certifications,
        title: 'Certifications',
        rows: p.certifications,
        empty: 'Add certificates you have earned, with a link recruiters can check.',
        card: (row, onRemove) {
          final credential = (row['credential_url'] as String?)?.trim() ?? '';
          return _entryCard(
            icon: Icons.verified_outlined,
            title: row['title'] as String? ?? '',
            subtitle: _joinParts([row['issuer'], monthYearLabel(row['date_earned'])]),
            onRemove: onRemove,
            actions: [
              if (credential.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _openLink(credential, 'credential'),
                  icon: Icon(Icons.open_in_new, size: 16),
                  label: Text('View credential'),
                ),
            ],
          );
        },
      ),
      _entrySection(
        section: PortfolioSection.badges,
        title: 'Badges',
        rows: p.badges,
        empty: 'Digital badges from Credly, Microsoft Learn, Google, AWS and the like — with the link.',
        card: (row, onRemove) {
          final url = (row['credential_url'] as String?)?.trim() ?? '';
          final isCredly = url.toLowerCase().contains('credly.com');
          return _entryCard(
            icon: Icons.military_tech_outlined,
            title: row['title'] as String? ?? '',
            subtitle: _joinParts([row['issuer'], monthYearLabel(row['date_earned'])]),
            onRemove: onRemove,
            actions: [
              if (url.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _openLink(url, 'badge'),
                  icon: Icon(Icons.open_in_new, size: 16),
                  label: Text(isCredly ? 'View on Credly' : 'View badge'),
                ),
            ],
          );
        },
      ),
      _entrySection(
        section: PortfolioSection.leadership,
        title: 'Leadership',
        rows: p.leadership,
        empty: 'Class rep, society committee, SRC, tutoring or team lead roles.',
        card: (row, onRemove) => _entryCard(
          icon: Icons.groups_outlined,
          title: row['role_title'] as String? ?? '',
          subtitle: row['organisation'] as String?,
          body: row['description'] as String?,
          onRemove: onRemove,
        ),
      ),
      _recommendationsSection(),
    ];
  }

  Widget _skillsSection() {
    final p = _portfolio;
    final skills = [...p.skills]
      ..sort((a, b) => p.endorsementsFor(b['id'] as String).compareTo(p.endorsementsFor(a['id'] as String)));
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Skills & endorsements',
            trailing: 'Suggest skills',
            onTrailingTap: () => _openCareerAiSheet(context),
          ),
          if (skills.isEmpty)
            Text('No skills yet. Career AI can suggest skills for your programme, or pull them from your CV.',
                style: _muted)
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in skills)
                  Chip(
                    label: Text(p.endorsementsFor(s['id'] as String) == 0
                        ? s['skill_name'] as String? ?? ''
                        : '${s['skill_name']} • ${p.endorsementsFor(s['id'] as String)}'),
                  ),
              ],
            ),
            SizedBox(height: AppSpace.xs),
            Text(
              p.endorsements.isEmpty
                  ? 'Connections can endorse these from your profile.'
                  : '${p.endorsements.length} endorsement${p.endorsements.length == 1 ? '' : 's'} from your network.',
              style: _muted,
            ),
          ],
        ],
      ),
    );
  }

  /// "CV on file" evidence (rubric Section 3). The PDF lives in the private
  /// cvs bucket; View mints a short-lived signed URL and hands it to the
  /// system PDF viewer. Replace goes through the same CV import that
  /// stored it.
  Widget _cvEvidenceCard() {
    final status = _cvStatus;
    final path = status?.path;
    final uploaded = status?.uploadedAt;
    final hasCv = path != null;

    return RoundedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: hasCv ? AppColors.primaryContainer : AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  hasCv ? Icons.picture_as_pdf_outlined : Icons.upload_file_outlined,
                  color: hasCv ? AppColors.onPrimaryContainer : AppColors.onSurfaceVariant,
                ),
              ),
              SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hasCv ? 'CV on file' : 'No CV on file', style: AppText.labelLg()),
                    Text(
                      hasCv
                          ? (uploaded != null
                              ? 'Uploaded ${monthYearLabel(uploaded.toIso8601String()) ?? ''} · private: only you and administrators can open it'
                              : 'Private: only you and administrators can open it')
                          : 'Import your CV to fill in your profile and keep the PDF here as evidence.',
                      style: _muted,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: 4,
            children: hasCv
                ? [
                    TextButton.icon(
                      onPressed: _cvBusy ? null : _openCv,
                      icon: Icon(Icons.open_in_new, size: 16),
                      label: Text('View'),
                    ),
                    TextButton.icon(
                      onPressed: _cvBusy ? null : _openCvImport,
                      icon: Icon(Icons.autorenew, size: 16),
                      label: Text('Replace'),
                    ),
                    TextButton.icon(
                      onPressed: _cvBusy ? null : _removeCv,
                      icon: Icon(Icons.delete_outline, size: 16, color: AppColors.error),
                      label: Text('Remove', style: TextStyle(color: AppColors.error)),
                    ),
                  ]
                : [
                    TextButton.icon(
                      onPressed: _openCvImport,
                      icon: Icon(Icons.upload_file_outlined, size: 16),
                      label: Text('Import my CV'),
                    ),
                  ],
          ),
        ],
      ),
    );
  }

  Widget _entrySection({
    required PortfolioSection section,
    required String title,
    required List<Map<String, dynamic>> rows,
    required String empty,
    required Widget Function(Map<String, dynamic> row, VoidCallback onRemove) card,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: title, trailing: '+ Add', onTrailingTap: () => _addEntry(section)),
          if (rows.isEmpty)
            Text(empty, style: _muted)
          else
            for (final row in rows) card(row, () => _removeEntry(section, row)),
        ],
      ),
    );
  }

  Widget _entryCard({
    required IconData icon,
    required String title,
    required VoidCallback onRemove,
    String? subtitle,
    String? body,
    List<Widget> actions = const [],
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpace.sm),
      child: RoundedCard(
        padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.xs, AppSpace.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(icon, size: 18, color: AppColors.secondary),
            ),
            SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.labelLg()),
                  if (subtitle != null && subtitle.isNotEmpty) Text(subtitle, style: _muted),
                  if (body != null && body.trim().isNotEmpty) ...[
                    SizedBox(height: 4),
                    Text(body.trim(), style: AppText.bodySm()),
                  ],
                  if (actions.isNotEmpty) Wrap(spacing: 4, children: actions),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              onPressed: onRemove,
              icon: Icon(Icons.delete_outline, size: 20, color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recommendationsSection() {
    final recommendations = _portfolio.recommendations;
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: 'Recommendations'),
          if (recommendations.isEmpty)
            Text('No recommendations yet. Alumni, lecturers and employers can write one from your profile.',
                style: _muted)
          else
            for (final r in recommendations) _recommendationCard(r),
        ],
      ),
    );
  }

  Widget _recommendationCard(Map<String, dynamic> r) {
    final authorRow = r['author'];
    final author = authorRow is Map
        ? PersonSummary.fromRow({...Map<String, dynamic>.from(authorRow), 'id': r['author_id']})
        : null;
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpace.sm),
      child: RoundedCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.format_quote, color: AppColors.outline),
                SizedBox(width: 4),
                Expanded(
                  child: Text(
                    r['body'] as String? ?? '',
                    style: AppText.bodyMd().copyWith(fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
            SizedBox(height: AppSpace.sm),
            Row(
              children: [
                ProfileAvatar(
                  firstName: author?.firstName,
                  lastName: author?.lastName,
                  avatarPath: author?.avatarPath,
                  radius: 14,
                ),
                SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(author?.name ?? 'Former member', style: AppText.labelMd()),
                      if ((author?.subtitle ?? '').isNotEmpty)
                        Text(
                          author!.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _muted,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Posts and reposts. There was no activity section at all before, which
  /// is why a repost never appeared anywhere on the reposter's profile.
  Widget _activitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: 'Posts & reposts'),
        if (_loadingActivity)
          Padding(
            padding: EdgeInsets.all(AppSpace.lg),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_activityError != null) ...[
          Text(_activityError!, style: AppText.bodySm(color: AppColors.error)),
          TextButton(onPressed: _loadActivity, child: Text('Try again')),
        ] else if (_activity.isEmpty)
          Text('Nothing yet. Posts you share and posts you repost from the Feed appear here.', style: _muted)
        else
          for (final item in _activity)
            Padding(
              padding: EdgeInsets.only(bottom: AppSpace.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (item.isRepost)
                    Padding(
                      padding: EdgeInsets.only(left: AppSpace.xs, bottom: 4),
                      child: Row(
                        children: [
                          Icon(Icons.repeat, size: 14, color: AppColors.onSurfaceVariant),
                          SizedBox(width: 4),
                          Text('You reposted', style: AppText.labelMd(color: AppColors.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  item.post.type == FeedPostType.text
                      ? _TextPostCard(
                          post: item.post,
                          onRepost: item.post.id == null ? null : () => _toggleRepost(item.post),
                          onReact: item.post.id == null ? null : () => _toggleReaction(item.post),
                          onComment: item.post.id == null ? null : () => _openComments(item.post),
                          onDelete: item.isRepost || item.post.id == null ? null : () => _deletePost(item),
                        )
                      : _VideoPostCard(
                          post: item.post,
                          onRepost: item.post.id == null ? null : () => _toggleRepost(item.post),
                          onReact: item.post.id == null ? null : () => _toggleReaction(item.post),
                          onComment: item.post.id == null ? null : () => _openComments(item.post),
                          onDelete: item.isRepost || item.post.id == null ? null : () => _deletePost(item),
                        ),
                ],
              ),
            ),
      ],
    );
  }
}

// =====================================================================
// SECTION 12 — RICHFIELD CAREER AI SHEET (profile assistant)
// =====================================================================

/// Entry point to Richfield Career AI from the Portfolio sparkle button.
///
/// Everything on this sheet used to be hardcoded: a 'PRO' badge, a
/// '+65% REACH' stat with no source, a 'GitHub Sync Ready' feature that did
/// not exist, and an 'NLP CV Parser' card describing an upload flow with no
/// tap target. Profile strength and next steps now come from the user's real
/// rows (ProfileContext), and every card opens something that works. It pops
/// with the screen to open — see PortfolioScreen._openCareerAiSheet.
class RichfieldCareerAiSheet extends StatefulWidget {
  RichfieldCareerAiSheet({super.key});

  @override
  State<RichfieldCareerAiSheet> createState() => _RichfieldCareerAiSheetState();
}

class _RichfieldCareerAiSheetState extends State<RichfieldCareerAiSheet> {
  final _contextService = ProfileContextService(Supabase.instance.client);
  ProfileContext? _ctx;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final ctx = await _contextService.load(userId);
      if (mounted) setState(() => _ctx = ctx);
    } catch (e) {
      if (mounted) setState(() => _error = AuthErrorMapper.fromAny(e));
    }
  }

  void _open(Widget screen) => Navigator.pop(context, screen);

  String _strengthLabel(double completeness) {
    final pct = (completeness * 100).round();
    if (pct >= 100) return 'COMPLETE';
    if (pct >= 70) return 'STRONG PROFILE';
    if (pct >= 40) return 'GOOD START';
    return 'JUST GETTING STARTED';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        final ctx = _ctx;
        final next = ctx?.nextStep;
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.all(AppSpace.base),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: EdgeInsets.only(bottom: AppSpace.md),
                  decoration: BoxDecoration(
                    color: AppColors.outlineVariant,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(Icons.smart_toy_outlined, color: AppColors.onPrimary),
                  ),
                  SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Richfield Career AI', style: AppText.labelLg()),
                        Text('Profile assistant powered by Google Gemini',
                            style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.expand_more),
                  ),
                ],
              ),
              SizedBox(height: AppSpace.base),
              if (ctx == null && _error == null)
                Padding(
                  padding: EdgeInsets.all(AppSpace.xl),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_error != null) Text(_error!, style: AppText.bodySm(color: AppColors.error)),
              if (ctx != null) ...[
                _strengthCard(ctx),
                SizedBox(height: AppSpace.md),
                if (next != null) ...[
                  Text('NEXT STEPS', style: AppText.labelBadge(color: AppColors.onSurfaceVariant)),
                  SizedBox(height: 6),
                  ...ctx.steps.where((s) => !s.done).take(3).map(
                        (step) => Padding(
                          padding: EdgeInsets.only(bottom: AppSpace.sm),
                          child: _actionCard(
                            icon: Icons.flag_outlined,
                            iconBg: AppColors.tertiaryContainer,
                            title: step.label,
                            body: step.why,
                            cta: 'Ask AI',
                            onTap: () => _open(AiAssistantScreen(initialMessage: step.prompt)),
                          ),
                        ),
                      ),
                ],
                _actionCard(
                  icon: Icons.description_outlined,
                  iconBg: AppColors.secondaryContainer,
                  title: 'Import from your CV',
                  body: 'Upload your CV as a PDF, or paste it. AI extracts a headline, skills '
                      'and education for you to review before anything is saved.',
                  cta: 'Import',
                  onTap: () => _open(CvImportScreen()),
                ),
                SizedBox(height: AppSpace.base),
                Text('ASK THE ASSISTANT', style: AppText.labelBadge(color: AppColors.onSurfaceVariant)),
                SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _queryChip('What do tech recruiters look for?'),
                    _queryChip('How do I improve my profile?'),
                    _queryChip('Which roles fit my skills?'),
                  ],
                ),
                SizedBox(height: AppSpace.base),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _open(AiAssistantScreen()),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: AppColors.outlineVariant),
                        ),
                        child: Text('Open chat', style: AppText.labelLg()),
                      ),
                    ),
                    SizedBox(width: AppSpace.sm),
                    Expanded(
                      flex: 2,
                      child: PrimaryButton(
                        label: next == null ? 'Review my profile' : 'Start guided setup',
                        icon: Icons.auto_awesome,
                        onPressed: () => _open(next == null
                            ? AiAssistantScreen(
                                initialMessage:
                                    'Review my profile and tell me what would make it stand out more.')
                            : AiAssistantScreen(guided: true)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _strengthCard(ProfileContext ctx) {
    final pct = (ctx.completeness * 100).round();
    final missing = ctx.steps.length - ctx.doneCount;
    return RoundedCard(
      color: AppColors.surfaceContainerLow,
      border: Border.all(color: Colors.transparent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt, color: AppColors.tertiary, size: 16),
              SizedBox(width: 4),
              Text('$pct% Profile Strength', style: AppText.labelLg()),
              Spacer(),
              Text(_strengthLabel(ctx.completeness),
                  style: AppText.labelBadge(color: AppColors.onSurfaceVariant)),
            ],
          ),
          SizedBox(height: AppSpace.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              value: ctx.completeness,
              minHeight: 8,
              backgroundColor: AppColors.surfaceContainerHigh,
              color: AppColors.primary,
            ),
          ),
          SizedBox(height: AppSpace.sm),
          Text(
            missing == 0
                ? 'Every setup step is done — nice work.'
                : '${ctx.doneCount} of ${ctx.steps.length} setup steps done, $missing to go.',
            style: AppText.bodySm(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required Color iconBg,
    required String title,
    required String body,
    required String cta,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: RoundedCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconBg.withOpacity(0.4),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(icon, size: 18, color: AppColors.onSurface),
            ),
            SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.labelLg()),
                  SizedBox(height: 2),
                  Text(body, style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            SizedBox(width: AppSpace.sm),
            Text(cta, style: AppText.labelMd(color: AppColors.primary)),
          ],
        ),
      ),
    );
  }

  Widget _queryChip(String text) {
    return ActionChip(
      avatar: Icon(Icons.chat_bubble_outline, size: 14, color: AppColors.onSurfaceVariant),
      label: Text(text, style: AppText.bodySm()),
      onPressed: () => _open(AiAssistantScreen(initialMessage: text)),
      backgroundColor: AppColors.surfaceContainerLow,
      side: BorderSide(color: AppColors.outlineVariant),
    );
  }
}

// =====================================================================
// SECTION 13 — ONBOARDING TOUR OVERLAY
// Simplified coach-mark sequence. In production, anchor each step to the
// real widget's position with a GlobalKey + RenderBox instead of the
// fixed offsets used here.
// =====================================================================

class OnboardingTourOverlay extends StatefulWidget {
  OnboardingTourOverlay({super.key});

  @override
  State<OnboardingTourOverlay> createState() => _OnboardingTourOverlayState();
}

class _OnboardingTourOverlayState extends State<OnboardingTourOverlay> {
  int _step = 0;

  static final _steps = [
    (
      title: 'STEP 1 OF 4: WELCOME',
      body: "This is your Portfolio — think of it as your always-on digital CV. Recruiters see this before they see you.",
      top: 0.18,
    ),
    (
      title: 'STEP 2 OF 4: YOUR INSTITUTIONAL SUPERPOWER',
      body: "Unlike typical public profiles, your @my.richfield.ac.za verification proves your academic integrity to 150+ vetted employers instantly. Recruiters search specifically for accredited Richfield talent!",
      top: 0.32,
    ),
    (
      title: 'STEP 3 OF 4: LET AI DO THE WORK',
      body: "Tap the sparkle button any time to open Richfield Career AI — it reviews your profile and suggests the fastest ways to get noticed.",
      top: 0.5,
    ),
    (
      title: 'STEP 4 OF 4: STAY VISIBLE',
      body: "Use the Recruiter Visibility toggle to control exactly what accredited partners can see. You're always in control of your data.",
      top: 0.68,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    final screenHeight = MediaQuery.of(context).size.height;

    return Material(
      color: Colors.black54,
      child: Stack(
        children: [
          Positioned(
            left: AppSpace.base,
            right: AppSpace.base,
            top: screenHeight * step.top,
            child: Container(
              padding: EdgeInsets.all(AppSpace.base),
              decoration: BoxDecoration(
                color: AppColors.inverseSurface,
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(step.title,
                          style: AppText.labelBadge(color: AppColors.tertiaryFixedDim)),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Text('Skip Tour',
                            style: AppText.labelMd(
                                color: AppColors.inverseOnSurface.withOpacity(0.7))),
                      ),
                    ],
                  ),
                  SizedBox(height: AppSpace.sm),
                  Text(step.body,
                      style: AppText.bodyMd(color: AppColors.inverseOnSurface)),
                  SizedBox(height: AppSpace.md),
                  Row(
                    children: [
                      Row(
                        children: List.generate(_steps.length, (i) {
                          final active = i == _step;
                          return Container(
                            margin: EdgeInsets.only(right: 4),
                            width: active ? 16 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: active
                                  ? AppColors.primary
                                  : AppColors.inverseOnSurface.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(AppRadius.full),
                            ),
                          );
                        }),
                      ),
                      Spacer(),
                      if (_step > 0)
                        TextButton(
                          onPressed: () => setState(() => _step -= 1),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size(0, 0),
                          ),
                          child: Text('Back',
                              style: AppText.labelLg(
                                  color: AppColors.inverseOnSurface.withOpacity(0.7))),
                        ),
                      ElevatedButton(
                        onPressed: () {
                          if (_step == _steps.length - 1) {
                            Navigator.pop(context);
                          } else {
                            setState(() => _step += 1);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        child: Text(_step == _steps.length - 1 ? 'Done' : 'Next'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
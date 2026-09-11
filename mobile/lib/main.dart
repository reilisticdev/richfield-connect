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
//   - Everything else is still UI-layer prototype: the "MOCK DATA" section
//     below (FeedScreen, Jobs/Network/Portfolio content, dashboards) is
//     still sample data, not wired to real tables. That's the known,
//     deliberate scope of this pass — swap it out next.
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
import 'services/profile_context_service.dart';
import 'screens/messages_screen.dart';
import 'screens/network_screen.dart';
import 'screens/notifications_screen.dart';
import 'services/notifications_service.dart';
import 'services/realtime_hub.dart';

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
        return 'Verified Graduate';
      case RichfieldRole.corporate:
        return 'Partner Recruiter';
      case RichfieldRole.admin:
        return 'Gateway Portal';
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

class Credential {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final String tag;

  Credential({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.tag,
  });
}

class RepoProject {
  final String title;
  final String status;
  final String description;
  final List<String> stack;
  final int stars;
  final bool hasLiveDemo;

  RepoProject({
    required this.title,
    required this.status,
    required this.description,
    required this.stack,
    required this.stars,
    this.hasLiveDemo = true,
  });
}

class EndorsementSkill {
  final String skill;
  final int count;
  final Color accent;

  EndorsementSkill({
    required this.skill,
    required this.count,
    required this.accent,
  });
}

class LeadershipRole {
  final IconData icon;
  final Color iconBg;
  final String title;
  final String org;
  final String period;
  final String description;

  LeadershipRole({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.org,
    required this.period,
    required this.description,
  });
}

class Recommendation {
  final String quote;
  final String name;
  final String title;
  final bool facultyEndorsed;

  Recommendation({
    required this.quote,
    required this.name,
    required this.title,
    this.facultyEndorsed = false,
  });
}

enum FeedPostType { text, video }

class FeedPost {
  /// Database id. Null for the MockData rows, which have no backing row —
  /// engagement actions are disabled for those rather than pretending.
  final String? id;

  /// Public CDN url for an image post (posts.image_path resolved through
  /// the post-media bucket). Null for text-only and video posts.
  final String? imageUrl;

  /// Whether the signed-in user has already reposted this.
  final bool isReposted;

  final FeedPostType type;
  final String authorName;
  final String authorRole;
  final bool verified;
  final String timeAgo;
  final String body;
  final String? hashtag;
  final JobHighlight? job;
  final String? videoLabel;
  final String? videoDuration;
  final List<String>? featuredProjects;
  final int reactionCountA;
  final int reactionCountB;
  final int reactionCountC;

  FeedPost({
    this.id,
    this.imageUrl,
    this.isReposted = false,
    required this.type,
    required this.authorName,
    required this.authorRole,
    required this.verified,
    required this.timeAgo,
    required this.body,
    this.hashtag,
    this.job,
    this.videoLabel,
    this.videoDuration,
    this.featuredProjects,
    required this.reactionCountA,
    required this.reactionCountB,
    required this.reactionCountC,
  });

  /// Cheap immutable update so the feed can flip one card's repost state
  /// without re-querying the whole list.
  FeedPost copyWith({bool? isReposted, int? reactionCountC}) {
    return FeedPost(
      id: id,
      imageUrl: imageUrl,
      isReposted: isReposted ?? this.isReposted,
      type: type,
      authorName: authorName,
      authorRole: authorRole,
      verified: verified,
      timeAgo: timeAgo,
      body: body,
      hashtag: hashtag,
      job: job,
      videoLabel: videoLabel,
      videoDuration: videoDuration,
      featuredProjects: featuredProjects,
      reactionCountA: reactionCountA,
      reactionCountB: reactionCountB,
      reactionCountC: reactionCountC ?? this.reactionCountC,
    );
  }
}

class JobHighlight {
  final String title;
  final String company;
  final String location;
  final List<String> tags;
  final String slots;

  JobHighlight({
    required this.title,
    required this.company,
    required this.location,
    required this.tags,
    required this.slots,
  });
}

// Maps a real `posts` row (joined to `profiles` for the author) onto the
// existing FeedPost UI model, so FeedScreen's card widgets don't need to
// change — only where the data comes from.
FeedPost _feedPostFromRow(
  Map<String, dynamic> row, {
  Set<String> repostedIds = const <String>{},
  MediaService? mediaService,
}) {
  final profile = row['profiles'] as Map<String, dynamic>?;
  final id = row['id'] as String?;
  final imagePath = row['image_path'] as String?;

  // post_reposts(count) is a PostgREST aggregate embed: it comes back as
  // [{'count': n}], or an empty list when nothing references this post.
  final repostRows = row['post_reposts'];
  var repostCount = 0;
  if (repostRows is List && repostRows.isNotEmpty) {
    final first = repostRows.first;
    if (first is Map && first['count'] is int) repostCount = first['count'] as int;
  }
  final name = ('${profile?['first_name'] ?? ''} ${profile?['last_name'] ?? ''}').trim();
  final role = profile?['role'] as String?;
  final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now();
  return FeedPost(
    id: id,
    imageUrl: (imagePath != null && imagePath.isNotEmpty && mediaService != null)
        ? mediaService.postImageUrl(imagePath)
        : null,
    isReposted: id != null && repostedIds.contains(id),
    type: row['video_path'] != null ? FeedPostType.video : FeedPostType.text,
    authorName: name.isEmpty ? 'Richfield Member' : name,
    authorRole: role == null || role.isEmpty ? '' : role[0].toUpperCase() + role.substring(1),
    verified: true,
    timeAgo: _timeAgo(createdAt),
    body: row['body'] as String? ?? '',
    videoLabel: row['video_path'] != null ? 'Video post' : null,
    videoDuration: row['video_path'] != null ? '' : null,
    reactionCountA: 0,
    reactionCountB: 0,
    reactionCountC: repostCount,
  );
}

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

class JobListing {
  final String title;
  final String company;
  final String location;
  final String type;
  final List<String> skills;
  final bool approved;

  JobListing({
    required this.title,
    required this.company,
    required this.location,
    required this.type,
    required this.skills,
    this.approved = true,
  });
}

class ConnectionSuggestion {
  final String name;
  final String subtitle;
  final String initials;

  ConnectionSuggestion({
    required this.name,
    required this.subtitle,
    required this.initials,
  });
}

class MockData {
  MockData._();

  static List<Credential> get credentials => [
    Credential(
      icon: Icons.cloud_done_outlined,
      iconColor: AppColors.secondary,
      iconBg: AppColors.secondaryContainer,
      title: 'AWS Certified Cloud Practitioner',
      subtitle: 'Amazon Web Services — Verify ID: AWS-7890241 — Exp 2027',
      tag: '',
    ),
    Credential(
      icon: Icons.military_tech_outlined,
      iconColor: AppColors.primary,
      iconBg: AppColors.onPrimaryContainer,
      title: "Dean's Commendation 2024",
      subtitle: 'Richfield Faculty of IT — Top 1% GPA',
      tag: 'Ref: RF-ACAD-2024-SK',
    ),
    Credential(
      icon: Icons.emoji_events_outlined,
      iconColor: AppColors.tertiary,
      iconBg: AppColors.tertiaryContainer,
      title: 'Hackathon 1st Runner-Up',
      subtitle: 'FinTech Disrupt SA 2024 Challenge — Real-time Payments',
      tag: '',
    ),
  ];

  static final repos = [
    RepoProject(
      title: 'Richfield Campus Navigator',
      status: 'Production Ready',
      description:
          'Cross-platform indoor navigation & timetable coordination system for students with live campus beacon triangulation.',
      stack: ['React Native', 'Supabase', 'TypeScript', 'Mapbox GL'],
      stars: 42,
    ),
    RepoProject(
      title: 'FinTech Micro-Savings Engine',
      status: 'MIT Licensed',
      description:
          'High-throughput asynchronous banking core with automated round-up savings routines and ISO 20022 compliant messaging.',
      stack: ['Golang', 'PostgreSQL', 'Docker', 'gRPC'],
      stars: 28,
    ),
  ];

  static List<EndorsementSkill> get endorsements => [
    EndorsementSkill(skill: 'TypeScript', count: 14, accent: AppColors.secondary),
    EndorsementSkill(skill: 'Flutter & Dart', count: 10, accent: AppColors.primary),
    EndorsementSkill(skill: 'PostgreSQL', count: 8, accent: AppColors.tertiary),
    EndorsementSkill(skill: 'Python & ML', count: 11, accent: AppColors.successGreen),
  ];

  static List<LeadershipRole> get leadership => [
    LeadershipRole(
      icon: Icons.badge_outlined,
      iconBg: AppColors.onPrimaryContainer,
      title: 'SRC Technology Officer',
      org: 'Richfield Student Representative Council',
      period: '2024 – 2025',
      description:
          'Spearheaded the digitisation of student guild election voting systems, driving 78% student turnout without downtime.',
    ),
    LeadershipRole(
      icon: Icons.hub_outlined,
      iconBg: AppColors.secondaryContainer,
      title: 'Google DSC Lead',
      org: 'Developer Student Club Braamfontein',
      period: '2023 – 2024',
      description:
          'Organised weekly peer coding clinics, mentoring over 120 lower-cohort students in Git workflows and cloud deployments.',
    ),
  ];

  static final recommendations = [
    Recommendation(
      quote:
          'Sipho has consistently demonstrated exceptional full-stack capabilities, analytical maturity, and rigorous systems thinking. His contribution to distributed microservices research ranks him among the top software scholars our campus has fostered in the past decade.',
      name: 'Dr. N. Pillay, Ph.D.',
      title: 'Senior Lecturer, Faculty of Information Technology',
      facultyEndorsed: true,
    ),
  ];

  static final feedPosts = [
    FeedPost(
      type: FeedPostType.text,
      authorName: 'Thabo Ndlovu',
      authorRole: "Senior Software Engineer at Discover... — Alumni '21",
      verified: true,
      timeAgo: '3h ago',
      body:
          "Excited to share that our engineering team at Discovery is opening 15 graduate internship slots for Richfield BSc IT & Computer Science graduates! Check the Opportunities tab or apply with your Richfield verified profile.",
      job: JobHighlight(
        title: 'Junior Cloud & Backend Engineer',
        company: 'Discovery Digital Tech Campus',
        location: 'Sandton, JHB (Hybrid)',
        tags: ['Python', 'AWS CDK', 'Spring Boot', 'BSc IT 2024/2025'],
        slots: '15 SLOTS',
      ),
      reactionCountA: 142,
      reactionCountB: 38,
      reactionCountC: 19,
    ),
    FeedPost(
      type: FeedPostType.video,
      authorName: 'Amara Okafor',
      authorRole: 'Student Ambassador & Full-Stack Dev... — 3rd Year IT',
      verified: true,
      timeAgo: '5h ago',
      body:
          'Day in the life of a Richfield final year student prepping for the annual hackathon!',
      hashtag: '#TechInSA #RichfieldGrads',
      videoLabel: 'Richfield Cloud Transcoded 1080p',
      videoDuration: '01:24',
      featuredProjects: ['FinTech Microservices', 'AWS DynamoDB'],
      reactionCountA: 289,
      reactionCountB: 52,
      reactionCountC: 1400,
    ),
  ];

  static final jobs = [
    JobListing(
      title: 'Graduate Software Engineer',
      company: 'Standard Bank Digital',
      location: 'Rosebank, JHB (Hybrid)',
      type: 'Graduate Programme',
      skills: ['Java', 'Kotlin', 'REST APIs'],
    ),
    JobListing(
      title: 'Data Analyst Intern',
      company: 'Vodacom Insights Lab',
      location: 'Midrand, JHB (On-site)',
      type: 'Internship',
      skills: ['SQL', 'Python', 'Power BI'],
    ),
    JobListing(
      title: 'Mobile Engineer (Flutter)',
      company: 'Naspers Labs',
      location: 'Cape Town (Remote)',
      type: 'Learnership',
      skills: ['Flutter', 'Dart', 'Firebase'],
    ),
  ];

  static final suggestions = [
    ConnectionSuggestion(
      name: 'Priya Naidoo',
      subtitle: 'BCom Business Admin — Class of 2025',
      initials: 'PN',
    ),
    ConnectionSuggestion(
      name: 'Karabo Sekhu',
      subtitle: 'Recruiter @ Absa Tech',
      initials: 'KS',
    ),
    ConnectionSuggestion(
      name: 'Liam van der Merwe',
      subtitle: 'BSc IT — Alumni 2022',
      initials: 'LV',
    ),
  ];
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
  bool _trustDevice = true;
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
              RoundedCard(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: AppColors.onPrimaryContainer.withOpacity(0.3),
                border: Border.all(color: Colors.transparent),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, size: 18, color: AppColors.primary),
                    SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Richfield Secure Vault Initialising…', style: AppText.labelMd()),
                          Text('256-Bit Hardware Handshake',
                              style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Text('VAULT ONLINE',
                        style: AppText.labelBadge(color: AppColors.primary)),
                  ],
                ),
              ),
              SizedBox(height: AppSpace.xl),
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
                  SizedBox(width: AppSpace.sm),
                  Pill(
                    text: '256-Bit Vault',
                    background: AppColors.errorContainer,
                    foreground: AppColors.error,
                    icon: Icons.shield_outlined,
                  ),
                ],
              ),
              SizedBox(height: AppSpace.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Select Access', style: AppText.labelLg()),
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
                          Text('Student Domain Policy', style: AppText.labelMd()),
                          SizedBox(height: 2),
                          Text(
                            'Direct instant sign-in requires an authentic institutional inbox (@my.richfield.ac.za or @my.aaa.ac.za).',
                            style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: AppSpace.base),
              OutlinedButton.icon(
                onPressed: _signIn,
                icon: Icon(Icons.g_mobiledata, size: 28, color: AppColors.onSurface),
                label: Text('Continue with Institutional Google', style: AppText.labelLg()),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: AppColors.outlineVariant),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                ),
              ),
              SizedBox(height: AppSpace.base),
              Row(
                children: [
                  Expanded(child: Divider(color: AppColors.outlineVariant)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('OR CREDENTIALS LOGIN',
                        style: AppText.labelBadge(color: AppColors.onSurfaceVariant)),
                  ),
                  Expanded(child: Divider(color: AppColors.outlineVariant)),
                ],
              ),
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
                    hintText: _selectedRole == RichfieldRole.corporate
                      ? 'name@company.co.za'
                      : _selectedRole == RichfieldRole.admin
                        ? 'admin@richfield.ac.za'
                        : 'student.id',
                  suffixIcon: Padding(
                    padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    child: Pill(
                        text: _selectedRole == RichfieldRole.corporate
                          ? 'WORK EMAIL'
                          : _selectedRole == RichfieldRole.admin
                            ? '@richfield.ac.za'
                            : '@my.richfield',
                      background: AppColors.surfaceContainerHigh,
                      foreground: AppColors.onSurfaceVariant,
                    ),
                  ),
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
                  Text('Network', style: AppText.labelLg()),
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
              SizedBox(height: AppSpace.sm),
              CheckboxListTile(
                value: _trustDevice,
                onChanged: (v) => setState(() => _trustDevice = v ?? true),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('Trust this device for 30 days via Richfield Mobile Token',
                    style: AppText.bodySm()),
              ),
              if (_errorMessage != null) ...[
                Padding(
                  padding: EdgeInsets.only(bottom: AppSpace.sm),
                  child: Text(_errorMessage!, style: AppText.bodySm(color: AppColors.error)),
                ),
              ],
              SizedBox(height: AppSpace.sm),
              PrimaryButton(
                label: _submitting ? 'SIGNING IN…' : 'SIGN IN AS ${_selectedRole.label.toUpperCase()}',
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
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  static final _tabs = ['Student', 'Alumni', 'Employer'];
  static final _tabIcons = [Icons.school_outlined, Icons.workspace_premium_outlined, Icons.apartment_outlined];

  // No campuses lookup table exists in the DB (campus is a free-text
  // column elsewhere in the schema) and the selection isn't persisted on
  // signup yet — this list only makes the dropdown itself functional.
  static const _campuses = ['Braamfontein', 'Cape Town', 'Durban', 'Pretoria', 'Nelspruit', 'Vereeniging'];
  String _campus = _campuses.first;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
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

  Future<void> _submit() async {
    // Naive split of "Full Legal Name" into first/last on the first space —
    // a hackathon-pace shortcut, not a real name-parsing solution.
    final fullName = _fullNameController.text.trim();
    final spaceIndex = fullName.indexOf(' ');
    final firstName = spaceIndex == -1 ? (fullName.isEmpty ? null : fullName) : fullName.substring(0, spaceIndex);
    final lastName = spaceIndex == -1 ? null : fullName.substring(spaceIndex + 1).trim();

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await widget.authService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        role: _signupRole,
        firstName: firstName,
        lastName: lastName,
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
      appBar: AppBar(
        backgroundColor: AppColors.surfaceContainerLow,
        elevation: 0,
        foregroundColor: AppColors.onSurface,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(AppSpace.base),
          child: Column(
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
                'Verify your institutional credentials to connect directly with premier South African corporate recruiters and alumni circles.',
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
                        onTap: () => setState(() => _tab = i),
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
                      child: Icon(Icons.school_outlined, color: Colors.white, size: 18),
                    ),
                    SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_tabs[_tab]} Registration', style: AppText.labelLg()),
                          Text('Instant institutional database match via student email',
                              style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Pill(
                      text: 'ID VERIFIED',
                      background: AppColors.surfaceContainerLowest,
                      foreground: AppColors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              SizedBox(height: AppSpace.base),
              _labeledField('Full Legal Name', 'e.g. Sipho Nhlanhla Dlamini', Icons.person_outline,
                  controller: _fullNameController),
              SizedBox(height: AppSpace.md),
              if (_tab != 2) ...[
                _labeledField('Student Number', '202209148', Icons.badge_outlined),
                SizedBox(height: AppSpace.md),
              ],
                Text(_tab == 2 ? 'Business Work Email' : 'Mandatory Institutional Email',
                  style: AppText.labelLg()),
              SizedBox(height: 6),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.alternate_email, size: 18),
                  hintText: _tab == 2 ? 'recruiter@company.co.za' : 's.dlamini22',
                  suffixIcon: Padding(
                    padding: EdgeInsets.all(8),
                    child: Pill(
                      text: _tab == 2 ? 'WORK EMAIL' : '@my.richfield.ac.za',
                      background: AppColors.surfaceContainerHigh,
                      foreground: AppColors.onSurfaceVariant,
                      fontSize: 9,
                    ),
                  ),
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
                children: [
                  Icon(Icons.lock_outline, size: 12, color: AppColors.onSurfaceVariant),
                  SizedBox(width: 4),
                  Text('Domain suffix locked to accredited campus portals',
                      style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                ],
              ),
              SizedBox(height: AppSpace.md),
              _tab == 2
                  ? _labeledField('Company Location', 'Sandton, Johannesburg', Icons.location_on_outlined)
                  : Row(
                      children: [
                        Expanded(child: _campusDropdown()),
                        SizedBox(width: AppSpace.sm),
                        Expanded(child: _labeledField('Expected Year', '2025', Icons.calendar_today_outlined)),
                      ],
                    ),
              SizedBox(height: AppSpace.md),
              _tab == 2
                  ? _labeledField('Industry / Talent Focus', 'Software engineering and data', Icons.business_center_outlined)
                  : _labeledField('Faculty / Programme', 'BSc Information Technology', Icons.school_outlined),
              SizedBox(height: AppSpace.md),
              _labeledField('Password', 'At least 8 characters', Icons.lock_outline,
                  controller: _passwordController, obscureText: true),
              SizedBox(height: AppSpace.base),
              CheckboxListTile(
                value: _agreed,
                onChanged: (v) => setState(() => _agreed = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text.rich(
                  TextSpan(
                    style: AppText.bodySm(),
                    children: [
                      TextSpan(text: 'I agree to the '),
                      TextSpan(
                        text: 'Richfield Network POPIA Terms',
                        style: AppText.bodySm(color: AppColors.primary),
                      ),
                      TextSpan(
                          text: ' and consent to cross-matching my identity with institutional registrar databases.'),
                    ],
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                Padding(
                  padding: EdgeInsets.only(bottom: AppSpace.sm),
                  child: Text(_errorMessage!, style: AppText.bodySm(color: AppColors.error)),
                ),
              ],
              SizedBox(height: AppSpace.sm),
              PrimaryButton(
                label: _submitting ? 'Creating account…' : 'Create Verified ${_tabs[_tab]} Account',
                icon: Icons.how_to_reg_outlined,
                onPressed: (_agreed && !_submitting) ? _submit : null,
              ),
              SizedBox(height: AppSpace.sm),
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline, size: 12, color: AppColors.successGreen),
                    SizedBox(width: 4),
                    Text('Supabase Auth Ready for Backend Integration',
                        style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
              SizedBox(height: AppSpace.base),
              RoundedCard(
                color: AppColors.tertiaryContainer.withOpacity(0.15),
                border: Border.all(color: Colors.transparent),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.tertiaryFixed,
                      child: Text('92%', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700)),
                    ),
                    SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Graduate Placement Index', style: AppText.labelMd()),
                          Text('Class of 2024 placed within 6 months',
                              style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Icon(Icons.trending_up, color: AppColors.successGreen),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _labeledField(String label, String hint, IconData icon,
      {TextEditingController? controller, bool obscureText = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.labelLg()),
        SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
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

class AdminDashboardScreen extends StatelessWidget {
  AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(AppSpace.base, AppSpace.sm, AppSpace.base, 24),
      children: [
        RichfieldHeader(
          title: 'Admin Analytics',
          subtitle: 'STAFF TIER 1',
          onAvatarTap: () => _openAccountMenu(context, AuthService(Supabase.instance.client)),
        ),
        _dashboardBanner('Canvas Core: Ready for Deployment', AppColors.successGreen),
        SizedBox(height: AppSpace.base),
        SectionHeader(title: 'Operational Tickers'),
        _metricGrid([
          ['12', 'Alumni Queue', Icons.shield_outlined],
          ['4', 'Biz Approvals', Icons.business_center_outlined],
          ['1', 'Moderation', Icons.flag_outlined],
          ['3,420', 'Students', Icons.groups_outlined],
        ]),
        SizedBox(height: AppSpace.base),
        SectionHeader(title: 'Platform Growth & Ingestion'),
        RoundedCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Platform Growth', style: AppText.headlineSm()),
          Text('Live operational analytics for institutional oversight', style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
          SizedBox(height: AppSpace.md),
          SizedBox(height: 110, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [18, 34, 52, 70, 86, 100].map((value) => Expanded(child: Padding(padding: EdgeInsets.symmetric(horizontal: 3), child: Container(height: value.toDouble(), color: value == 100 ? AppColors.primary : AppColors.secondary)))).toList())),
          SizedBox(height: AppSpace.md),
          Text('Integration Hookpoints', style: AppText.labelLg()),
          _hookRow(context, Icons.manage_accounts_outlined, 'User Management Hook', 'Approve, suspend, and verify accounts'),
          _hookRow(context, Icons.flag_outlined, 'Moderation Pipeline', 'Review flagged feed content'),
          _hookRow(context, Icons.event_outlined, 'Events Dispatcher', 'Career fairs and hackathons'),
          _hookRow(context, Icons.business_center_outlined, 'Business Oversight', 'Recruiter and job approvals'),
        ])),
        SizedBox(height: AppSpace.base),
        SectionHeader(title: 'Pending Oversight Requests'),
        _oversightRow(context, 'Vodacom Enterprise Dev', 'Junior Cloud Architect', 'Authorize'),
        _oversightRow(context, 'Student Post Flagged', 'Off-topic commercial solicitation', 'Remove Post'),
      ],
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
      final businessId = _authService.currentUser?.id;
      if (businessId != null) {
        final bp = await Supabase.instance.client
            .from('business_profiles')
            .select('company_name')
            .eq('profile_id', businessId)
            .maybeSingle();
        companyName = (bp?['company_name'] as String?) ?? '';
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
        _dashboardBanner(
            _companyName.isEmpty ? 'Verified Partner' : '$_companyName • Verified Partner',
            AppColors.secondary),
        SizedBox(height: AppSpace.base),
        SectionHeader(title: 'Company Verification'),
        // Left as-is deliberately: business_profiles has no CIPC/MoA
        // verification columns in the schema, so there's nothing real to
        // swap these two rows for yet.
        _checkRow('CIPC Registration Verified', _companyName.isEmpty ? 'On file' : _companyName),
        _checkRow('Work Email Domain Verified', '@discovery.co.za'),
        _checkRow('Richfield Academic MoA', 'In review'),
        SizedBox(height: AppSpace.base),
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

Widget _hookRow(BuildContext context, IconData icon, String title, String detail) => Padding(
      padding: EdgeInsets.only(top: AppSpace.sm),
      child: Row(children: [Icon(icon, color: AppColors.secondary), SizedBox(width: AppSpace.sm), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: AppText.labelMd()), Text(detail, style: AppText.bodySm(color: AppColors.onSurfaceVariant))])), OutlinedButton(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$title attached'), duration: Duration(seconds: 1))), child: Text('Attach'))]),
    );

Widget _oversightRow(BuildContext context, String title, String detail, String action) => Padding(
      padding: EdgeInsets.only(bottom: AppSpace.sm),
      child: RoundedCard(child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: AppText.labelLg()), Text(detail, style: AppText.bodySm(color: AppColors.onSurfaceVariant))])), ElevatedButton(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$action completed'), duration: Duration(seconds: 1))), child: Text(action))])),
    );

Widget _checkRow(String title, String detail) => Padding(
      padding: EdgeInsets.only(bottom: AppSpace.sm),
      child: RoundedCard(child: Row(children: [Icon(title.contains('MoA') ? Icons.pending_outlined : Icons.check_circle, color: title.contains('MoA') ? AppColors.tertiary : AppColors.successGreen), SizedBox(width: AppSpace.sm), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: AppText.labelMd()), Text(detail, style: AppText.bodySm(color: AppColors.onSurfaceVariant))]))])),
    );

Widget _skillBar(String label, double value) => Padding(padding: EdgeInsets.only(top: AppSpace.sm), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: AppText.bodySm()), Text('${(value * 100).round()}%', style: AppText.labelMd())]), SizedBox(height: 4), LinearProgressIndicator(value: value, color: AppColors.secondary, backgroundColor: AppColors.surfaceContainerHigh)]));

class _EngagementPainter extends CustomPainter {
  final Color color;
  _EngagementPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var i = 0; i < 7; i++) {
      final point = Offset(size.width * i / 6, size.height * (i.isEven ? .75 : .2));
      if (i == 0) path.moveTo(point.dx, point.dy); else path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2);
  }
  @override
  bool shouldRepaint(covariant _EngagementPainter oldDelegate) => oldDelegate.color != color;
}

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
  bool _showPinnedBanner = true;
  static const _filters = ['All Updates', 'Career Reels', 'Graduate Jobs'];

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

  @override
  void initState() {
    super.initState();
    _loadPosts();
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
      ]);

      final rows = results[0] as List<Map<String, dynamic>>;
      final reposted =
          results.length > 1 ? results[1] as Set<String> : <String>{};

      if (!mounted) return;
      setState(() {
        _repostedIds = reposted;
        _posts = rows
            .map((row) => _feedPostFromRow(
                  row,
                  repostedIds: reposted,
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadPosts,
          child: ListView(
          padding: EdgeInsets.only(bottom: 90),
          children: [
            RichfieldHeader(
              title: 'Feed',
              subtitle: 'RICHFIELD VERIFIED',
              onAvatarTap: () => _openAccountMenu(context, _authService),
            ),
            _spotlightStories(),
            if (_showPinnedBanner)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpace.base),
                child: _pinnedEventBanner(context),
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
            if (!_loadingPosts && _postsError == null && _posts.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpace.base),
                child: Text('No posts yet.', style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
              ),
            if (!_loadingPosts && _postsError == null)
              ..._posts.where((post) => !_dismissedPosts.contains(post.authorName)).map(
                (post) => Padding(
                  padding: EdgeInsets.fromLTRB(
                      AppSpace.base, 0, AppSpace.base, AppSpace.base),
                  child: post.type == FeedPostType.text
                      ? _TextPostCard(
                          post: post,
                          // MockData posts have no id, so they get no
                          // handler and the button renders disabled.
                          onRepost:
                              post.id == null ? null : () => _toggleRepost(post),
                        )
                      : _VideoPostCard(post: post),
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

  Widget _spotlightStories() {
    final stories = ['Lerato M.', 'Dev Hackathon…', 'Standard Bank Grad…'];
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: AppSpace.base),
        children: [
          _storyBubble(
            child: Icon(Icons.add, color: AppColors.primary),
            label: 'Add Your\nCareer Reel',
            border: true,
          ),
          ...stories.map((s) => _storyBubble(
                child: Text(s.substring(0, 1), style: AppText.headlineSm(color: Colors.white)),
                label: s,
                live: s == stories.first,
                filled: true,
              )),
        ],
      ),
    );
  }

  Widget _storyBubble({
    required Widget child,
    required String label,
    bool border = false,
    bool filled = false,
    bool live = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(right: AppSpace.sm),
      child: SizedBox(
        width: 68,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? AppColors.secondaryContainer : AppColors.surfaceContainerLowest,
                    border: border ? Border.all(color: AppColors.primary, width: 1.5) : null,
                  ),
                  child: child,
                ),
                if (live)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Pill(
                      text: 'LIVE',
                      background: AppColors.primary,
                      foreground: Colors.white,
                      fontSize: 8,
                    ),
                  ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppText.bodySm(color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pinnedEventBanner(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(AppSpace.base),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: AppSpace.xs,
            children: [
              Pill(
                text: 'CAREER SERVICES PINNED',
                background: AppColors.tertiaryFixed,
                foreground: AppColors.onTertiaryContainer,
                icon: Icons.push_pin_outlined,
              ),
              IconButton(
                tooltip: 'Dismiss announcement',
                onPressed: () => setState(() => _showPinnedBanner = false),
                icon: Icon(Icons.close, color: Colors.white70, size: 18),
              ),
            ],
          ),
          SizedBox(height: AppSpace.sm),
          Text('Richfield Annual Career Fair 2025',
              style: AppText.headlineSm(color: Colors.white)),
          SizedBox(height: 4),
          Text(
            'Over 45 corporate tech partners (AWS, Discovery, Standard Bank, Vodacom) recruiting on-site. Ensure your digital portfolio transcript is synced & verified.',
            style: AppText.bodySm(color: Colors.white.withOpacity(0.85)),
          ),
          SizedBox(height: AppSpace.md),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: AppSpace.sm,
            children: [
              Icon(Icons.calendar_today_outlined, size: 14, color: Colors.white70),
              SizedBox(width: 4),
              SizedBox(
                width: 132,
                child: Text('18 - 20 October 2025', style: AppText.bodySm(color: Colors.white70)),
              ),
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
                child: Text('RSVP Pass →'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TextPostCard extends StatelessWidget {
  final FeedPost post;
  final VoidCallback? onRepost;
  _TextPostCard({required this.post, this.onRepost});

  @override
  Widget build(BuildContext context) {
    return RoundedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _postAuthorRow(post),
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
          if (post.job != null) ...[
            SizedBox(height: AppSpace.md),
            _jobHighlightCard(post.job!),
          ],
          SizedBox(height: AppSpace.sm),
          _reactionRow(
            aLabel: '${post.reactionCountA}', aIcon: Icons.thumb_up_alt_outlined,
            bLabel: '${post.reactionCountB} Comments', bIcon: Icons.mode_comment_outlined,
            cLabel: '${post.reactionCountC} Reposts', cIcon: Icons.repeat,
            actions: ['Endorse', 'Comment', 'Repost', 'Share'],
            actionIcons: [
              Icons.thumb_up_alt_outlined,
              Icons.mode_comment_outlined,
              Icons.repeat,
              Icons.share_outlined,
            ],
            // Endorse / Comment / Share have no tables behind them yet, so
            // they stay null and render disabled — honest, rather than a
            // button that looks live and does nothing.
            actionHandlers: [null, null, onRepost, null],
            activeActionIndex: post.isReposted ? 2 : null,
          ),
        ],
      ),
    );
  }

  Widget _jobHighlightCard(JobHighlight job) {
    return Container(
      padding: EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.title, style: AppText.labelLg()),
                    Text('${job.company} • ${job.location}',
                        style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
              Pill(
                text: job.slots,
                background: AppColors.onPrimaryContainer,
                foreground: AppColors.primary,
              ),
            ],
          ),
          SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: job.tags
                .map((t) => Pill(
                      text: t,
                      background: AppColors.surfaceContainerHigh,
                      foreground: AppColors.onSurfaceVariant,
                    ))
                .toList(),
          ),
          SizedBox(height: AppSpace.sm),
          Row(
            children: [
              Icon(Icons.bolt, size: 14, color: AppColors.tertiary),
              SizedBox(width: 4),
              Expanded(
                child: Text('1-Click Verified Submission',
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
              ),
            ],
          ),
          SizedBox(height: 6),
          PrimaryButton(label: 'Fast Apply with Verified Profile', icon: Icons.verified_outlined),
        ],
      ),
    );
  }
}

class _VideoPostCard extends StatelessWidget {
  final FeedPost post;
  _VideoPostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    return RoundedCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(AppSpace.base),
            child: _postAuthorRow(post),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpace.base),
            child: Text(post.body, style: AppText.bodyMd()),
          ),
          if (post.hashtag != null)
            Padding(
              padding: EdgeInsets.fromLTRB(AppSpace.base, 4, AppSpace.base, 0),
              child: Text(post.hashtag!, style: AppText.bodySm(color: AppColors.primary)),
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
                    child: Icon(Icons.laptop_mac_outlined, color: Colors.white24, size: 64),
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
                      icon: Icons.cloud_done_outlined,
                    ),
                  ),
                Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Icon(Icons.play_arrow, color: Colors.white, size: 28),
                  ),
                ),
                if (post.videoDuration != null)
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Pill(
                      text: post.videoDuration!,
                      background: Colors.black.withOpacity(0.55),
                      foreground: Colors.white,
                    ),
                  ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Row(
                    children: [
                      Icon(Icons.fiber_manual_record, color: AppColors.primary, size: 10),
                      SizedBox(width: 4),
                      Text('Career Reel',
                          style: AppText.labelBadge(color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (post.featuredProjects != null)
            Padding(
              padding: EdgeInsets.fromLTRB(AppSpace.base, AppSpace.sm, AppSpace.base, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Text('FEATURED PROJECTS: ',
                      style: AppText.labelBadge(color: AppColors.onSurfaceVariant)),
                  ...post.featuredProjects!.map((p) => Pill(
                        text: p,
                        background: AppColors.secondaryContainer.withOpacity(0.4),
                        foreground: AppColors.secondary,
                      )),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.all(AppSpace.base),
            child: _reactionRow(
              aLabel: '${post.reactionCountA}', aIcon: Icons.volunteer_activism_outlined,
              bLabel: '${post.reactionCountB} Comments', bIcon: Icons.mode_comment_outlined,
              cLabel: '${(post.reactionCountC / 1000).toStringAsFixed(1)}k Plays',
              cIcon: Icons.play_circle_outline,
              actions: ['Like', 'Share', 'Comment', 'Save'],
              actionIcons: [
                Icons.thumb_up_alt_outlined,
                Icons.share_outlined,
                Icons.mode_comment_outlined,
                Icons.bookmark_border,
              ],
            ),
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

class StudentAnalyticsScreen extends StatelessWidget {
  StudentAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Student Analytics')),
      body: ListView(padding: EdgeInsets.all(AppSpace.base), children: [
        Text('Your career signal', style: AppText.headlineLg()),
        Text('See how employers and your network discover your profile.', style: AppText.bodyMd(color: AppColors.onSurfaceVariant)),
        SizedBox(height: AppSpace.base),
        _metricGrid([
          ['482', 'Profile views', Icons.visibility_outlined],
          ['36', 'New connections', Icons.hub_outlined],
          ['1.4k', 'Post engagement', Icons.favorite_border],
          ['82%', 'Profile completeness', Icons.trending_up],
        ]),
        SizedBox(height: AppSpace.base),
        RoundedCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Profile views over time', style: AppText.labelLg()),
          SizedBox(height: AppSpace.sm),
          SizedBox(height: 100, child: CustomPaint(painter: _EngagementPainter(AppColors.primary))),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul'].map((label) => Text(label, style: AppText.bodySm(color: AppColors.onSurfaceVariant))).toList()),
        ])),
        SizedBox(height: AppSpace.sm),
        RoundedCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Most searched skills', style: AppText.labelLg()),
          _skillBar('Flutter & Dart', .86),
          _skillBar('Python & ML', .71),
          _skillBar('Cloud Architecture', .54),
        ])),
        SizedBox(height: AppSpace.sm),
        RoundedCard(child: Row(children: [Icon(Icons.groups_outlined, color: AppColors.secondary), SizedBox(width: AppSpace.sm), Expanded(child: Text('Your profile is more complete than 68% of students in your programme.', style: AppText.bodyMd()))])),
      ]),
    );
  }
}

Widget _postAuthorRow(FeedPost post) {
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
      Icon(Icons.more_horiz, color: AppColors.onSurfaceVariant),
    ],
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
  int? activeActionIndex,
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
          final active = activeActionIndex == i;
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

  static const _typeOptions = ['All', 'internship', 'learnership', 'part_time', 'graduate_vacancy'];
  static const _typeLabels = {
    'All': 'All',
    'internship': 'Internship',
    'learnership': 'Learnership',
    'part_time': 'Part-time',
    'graduate_vacancy': 'Graduate Vacancy',
  };

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
      final rows = await _jobsService.fetchApprovedOpportunities();
      if (!mounted) return;
      setState(() {
        _all = rows;
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

  List<Map<String, dynamic>> get _filtered => _all.where((o) {
        final matchesType = _typeFilter == 'All' || o['opportunity_type'] == _typeFilter;
        final title = (o['title'] as String? ?? '').toLowerCase();
        final matchesQuery = _query.isEmpty || title.contains(_query.toLowerCase());
        return matchesType && matchesQuery;
      }).toList();

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
    return ListView(
      padding: EdgeInsets.only(bottom: 24),
      children: [
        RichfieldHeader(
          title: 'Opportunities',
          subtitle: 'SMART-MATCHED FOR YOU',
          onAvatarTap: () => _openAccountMenu(context, _authService),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpace.base),
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
          padding: EdgeInsets.symmetric(horizontal: AppSpace.base),
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
        Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpace.base),
          child: SectionHeader(title: 'Matched to Your Profile'),
        ),
        if (_loading)
          Padding(
            padding: EdgeInsets.all(AppSpace.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (!_loading && _error != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpace.base),
            child: Text(_error!, style: AppText.bodySm(color: AppColors.error)),
          ),
        if (!_loading && _error == null && _filtered.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpace.base),
            child: Text('No opportunities match right now.',
                style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
          ),
        if (!_loading && _error == null)
          ..._filtered.map((job) {
            final business = job['profiles']?['business_profiles'] as Map<String, dynamic>?;
            final company = business?['company_name'] as String? ?? 'Unknown company';
            final location = business?['location'] as String? ?? '';
            final skills = (job['required_skills'] as List?)?.cast<String>() ?? [];
            return Padding(
              padding: EdgeInsets.fromLTRB(AppSpace.base, 0, AppSpace.base, AppSpace.sm),
              child: RoundedCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
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
                        Row(
                          children: [
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
                          ],
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Pill(
                            text: _typeLabels[job['opportunity_type']] ??
                                job['opportunity_type'] as String? ??
                                '',
                            background: AppColors.tertiaryContainer.withOpacity(0.3),
                            foreground: AppColors.tertiary,
                          ),
                        ),
                      ],
                    ),
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
          }),
      ],
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

class _PortfolioScreenState extends State<PortfolioScreen> {
  bool _recruiterVisible = true;
  bool _compactDensity = false;
  Map<String, dynamic>? _profile;

  final _profileService = ProfileService(Supabase.instance.client);
  final _mediaService = MediaService(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    widget.authService.fetchOwnProfile().then((p) {
      if (mounted) setState(() => _profile = p);
    }).catchError((_) {
      // Keep showing the placeholder header on failure — not fatal.
    });
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
        ListView(
          padding: EdgeInsets.only(bottom: 90),
          children: [
            RichfieldHeader(
              title: 'Portfolio',
              subtitle: 'RICHFIELD VERIFIED',
              extraAction: IconButton(
                tooltip: 'Open student analytics',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => StudentAnalyticsScreen()),
                ),
                icon: Icon(Icons.analytics_outlined),
              ),
              onAvatarTap: () => _openAccountMenu(context, widget.authService),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpace.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _profileHeaderCard(),
                  SizedBox(height: AppSpace.base),
                  _statsRow(),
                  SizedBox(height: AppSpace.base),
                  _socialLinksRow(),
                  SizedBox(height: AppSpace.md),
                  PrimaryButton(
                    label: 'Download Verified CV (PDF)',
                    icon: Icons.file_download_outlined,
                    // Left null deliberately: there is no CV generator
                    // behind this yet, and PrimaryButton renders a null
                    // onPressed as disabled. An honest disabled button
                    // beats one that looks live and swallows the tap.
                    onPressed: null,
                  ),
                  SizedBox(height: AppSpace.sm),
                  Row(
                    children: [
                      SecondaryButton(label: 'Share Profile', icon: Icons.ios_share),
                      SizedBox(width: AppSpace.sm),
                      // SecondaryButton.onPressed is an OPTIONAL parameter
                      // and this call site simply never passed one, so
                      // OutlinedButton received null and disabled itself.
                      // That — not a broken handler — is why Edit Details
                      // ignored every tap.
                      SecondaryButton(
                        label: 'Edit Details',
                        icon: Icons.edit_outlined,
                        onPressed: _openEditProfile,
                      ),
                    ],
                  ),
                  SizedBox(height: AppSpace.xl),
                  SectionHeader(title: 'Verified Credentials', trailing: '3 VERIFIED'),
                  ...MockData.credentials.map((c) => _credentialTile(c)),
                  SizedBox(height: AppSpace.lg),
                  SectionHeader(title: 'Featured Code & Repositories', trailing: 'View All (14)'),
                ],
              ),
            ),
            _repoCarousel(),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpace.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: AppSpace.lg),
                  SectionHeader(title: 'Technical Endorsements', trailing: 'Endorse Sipho'),
                  ...MockData.endorsements.map((e) => _endorsementRow(e)),
                  SizedBox(height: AppSpace.lg),
                  SectionHeader(title: 'Campus Leadership'),
                  ...MockData.leadership.map((l) => _leadershipCard(l)),
                  SizedBox(height: AppSpace.lg),
                  SectionHeader(title: 'Academic Recommendations'),
                  ...MockData.recommendations.map((r) => _recommendationCard(r)),
                  SizedBox(height: AppSpace.lg),
                  _recruiterVisibilityCard(),
                  SizedBox(height: AppSpace.xxl),
                ],
              ),
            ),
          ],
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
    await _reloadProfile();
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

  Widget _profileHeaderCard() {
    final firstName = _profile?['first_name'] as String? ?? '';
    final lastName = _profile?['last_name'] as String? ?? '';
    final fullName = ('$firstName $lastName').trim();
    final displayName = fullName.isEmpty ? 'Richfield Member' : fullName;
    final initials =
        (firstName.isNotEmpty ? firstName[0] : '') + (lastName.isNotEmpty ? lastName[0] : '');
    final headline = _profile?['professional_headline'] as String? ??
        'Final Year BSc IT Student | Full-Stack Developer & Cloud Enthusiast';
    final avatarPath = _profile?['avatar_path'] as String?;

    return RoundedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The camera badge was a decorative Container inside a Stack
              // with no GestureDetector or InkWell anywhere in the subtree
              // — it looked like a button but nothing in the widget tree
              // could receive a tap. The whole avatar is now the target.
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
                    Pill(
                      text: 'VERIFIED STUDENT • @my.richfield.ac.za',
                      background: AppColors.successGreenBg,
                      foreground: AppColors.successGreen,
                      icon: Icons.verified_user,
                      fontSize: 9,
                    ),
                    SizedBox(height: 6),
                    Text(displayName, style: AppText.headlineMd()),
                    Text(headline,
                        style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 12, color: AppColors.primary),
                        Text(' Braamfontein • \'25',
                            style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpace.sm),
          Text(
            'Specialising in distributed backend microservices and mobile application architecture.',
            style: AppText.bodySm(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _statsRow() {
    Widget stat(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(value, style: AppText.headlineMd(color: AppColors.primary)),
              Text(label, style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
            ],
          ),
        );
    return RoundedCard(
      child: Column(
        children: [
          Row(
            children: [
              stat('482', 'Network'),
              stat('18', 'Endorsements'),
              stat('94%', 'Profile Score'),
            ],
          ),
          Divider(height: AppSpace.lg, color: AppColors.outlineVariant),
          Row(
            children: [
              Icon(Icons.star, size: 14, color: AppColors.tertiaryFixedDim),
              SizedBox(width: 4),
              Text('Institutional Readiness', style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
              Spacer(),
              Pill(
                text: 'Top 5% Cohort',
                background: AppColors.tertiaryContainer.withOpacity(0.3),
                foreground: AppColors.tertiary,
              ),
            ],
          ),
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

  Widget _credentialTile(Credential c) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpace.sm),
      child: RoundedCard(
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.iconBg.withOpacity(0.4),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(c.icon, color: c.iconColor),
            ),
            SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.title, style: AppText.labelLg()),
                  Text(c.subtitle,
                      style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                  if (c.tag.isNotEmpty)
                    Text(c.tag, style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.check_circle, color: AppColors.successGreen, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _repoCarousel() {
    return SizedBox(
      height: 330,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: AppSpace.base),
        itemCount: MockData.repos.length,
        separatorBuilder: (_, __) => SizedBox(width: AppSpace.sm),
        itemBuilder: (_, i) {
          final repo = MockData.repos[i];
          return SizedBox(
            width: 280,
            child: RoundedCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Container(
                        height: 90,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.secondary, AppColors.inverseSurface],
                          ),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
                        ),
                        child: Center(
                          child: Icon(Icons.terminal, color: Colors.white38, size: 36),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Pill(
                          text: '★ ${repo.stars}',
                          background: Colors.black.withOpacity(0.5),
                          foreground: Colors.white,
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Pill(
                          text: repo.status,
                          background: AppColors.successGreenBg,
                          foreground: AppColors.successGreen,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.all(AppSpace.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(repo.title, style: AppText.labelLg()),
                        SizedBox(height: 2),
                        Text(
                          repo.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                        ),
                        SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: repo.stack
                              .map((t) => Pill(
                                    text: t,
                                    background: AppColors.surfaceContainerHigh,
                                    foreground: AppColors.onSurfaceVariant,
                                    fontSize: 9,
                                  ))
                              .toList(),
                        ),
                        SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            SizedBox(width: 126, child: OutlinedButton.icon(onPressed: () {}, icon: Icon(Icons.open_in_new, size: 14), label: Text('Live Demo', style: AppText.labelMd()))),
                            SizedBox(width: 126, child: OutlinedButton.icon(onPressed: () {}, icon: Icon(Icons.code, size: 14), label: Text('View Source', style: AppText.labelMd()))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _endorsementRow(EndorsementSkill e) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(e.skill, style: AppText.labelLg()),
          ),
          SizedBox(
            width: 60,
            height: 24,
            child: Stack(
              clipBehavior: Clip.none,
              children: List.generate(
                3,
                (i) => Positioned(
                  left: i * 14.0,
                  top: 0,
                  child: InitialsAvatar(
                    initials: '+',
                    radius: 11,
                    background: e.accent.withOpacity(0.25),
                    foreground: e.accent,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: AppSpace.sm),
          Pill(
            text: '${e.count}',
            background: e.accent.withOpacity(0.15),
            foreground: e.accent,
          ),
        ],
      ),
    );
  }

  Widget _leadershipCard(LeadershipRole l) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpace.sm),
      child: RoundedCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: l.iconBg.withOpacity(0.4),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(l.icon, color: AppColors.onSurface),
            ),
            SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(l.title, style: AppText.labelLg())),
                      Text(l.period, style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                  Text(l.org, style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                  SizedBox(height: 4),
                  Text(l.description, style: AppText.bodySm()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recommendationCard(Recommendation r) {
    return RoundedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r.facultyEndorsed)
            Padding(
              padding: EdgeInsets.only(bottom: AppSpace.sm),
              child: Pill(
                text: 'Faculty Endorsed',
                background: AppColors.secondaryContainer.withOpacity(0.4),
                foreground: AppColors.secondary,
              ),
            ),
          Row(
            children: [
              Icon(Icons.format_quote, color: AppColors.outline, size: 24),
              SizedBox(width: 4),
              Expanded(
                child: Text(
                  r.quote,
                  style: AppText.bodyMd().copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpace.sm),
          Text(r.name, style: AppText.labelLg()),
          Text(r.title, style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _recruiterVisibilityCard() {
    return RoundedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Recruiter Visibility', style: AppText.labelLg()),
                    Text('Public Placement Showcase',
                        style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
              Switch(
                value: _recruiterVisible,
                onChanged: (v) => setState(() => _recruiterVisible = v),
                activeColor: AppColors.primary,
              ),
            ],
          ),
          Text(
            'Allow accredited partner recruiters to initiate direct interview offers.',
            style: AppText.bodySm(color: AppColors.onSurfaceVariant),
          ),
          SizedBox(height: _compactDensity ? AppSpace.xs : AppSpace.sm),
          Text('Display Density & View Experience', style: AppText.labelMd()),
          SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _compactDensity = false),
                  icon: Icon(Icons.wb_sunny_outlined, size: 16),
                  label: Text('Comfortable', style: AppText.labelMd()),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: !_compactDensity ? AppColors.primary.withOpacity(.12) : null,
                  ),
                ),
              ),
              SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _compactDensity = true),
                  icon: Icon(Icons.text_fields, size: 16),
                  label: Text('Compact', style: AppText.labelMd()),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _compactDensity ? AppColors.primary.withOpacity(.12) : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
                  body: 'Paste your CV or describe your experience. AI extracts a headline, skills '
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
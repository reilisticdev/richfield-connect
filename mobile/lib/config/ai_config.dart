// mobile/lib/config/ai_config.dart
//
// Where the app finds the Python/Flask AI microservice (ai/app.py — CV
// parsing, skill suggestions and the onboarding chat).
//
// UNLIKE supabase_config.dart, this address is NOT stable. The service runs
// behind an ngrok tunnel whose URL can change when the tunnel restarts, so a
// URL committed to git is stale by the time anyone else pulls it, and
// rebuilding the APK just to change it costs minutes on demo day.
// Resolution order, first non-empty value wins:
//
//   1. An address saved on this device from the assistant's
//      "AI server address" dialog (SharedPreferences). A per-device
//      override, e.g. for testing another server; Reset clears it.
//   2. app_config.ai_base_url in Supabase (migration 035). An administrator
//      sets it once and every signed-in app picks it up on its next AI
//      request. This is the normal path.
//   3. --dart-define=AI_BASE_URL=https://<tunnel> passed to flutter run /
//      flutter build.
//   4. [placeholder], which fails with a clear message instead of quietly
//      pointing at somebody's dead tunnel.
//
// Before 035 only 1 and 3 existed, so a build without the dart-define
// (Keshav's QA build, 2026-09-11) had no address at all: every AI action
// said "The AI server address hasn't been set" while the service was up.
//
// Check an address is live with:  curl <url>/health
// It should return {"status":"ok","gemini_configured":true,...}.

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AiConfig {
  AiConfig._();

  static const placeholder = 'https://REPLACE-WITH-CURRENT-NGROK-URL.ngrok-free.app';
  static const _fromBuild = String.fromEnvironment('AI_BASE_URL');
  static const _prefsKey = 'richfield_ai_base_url';
  static const _remoteKey = 'ai_base_url';

  /// How long a value read from app_config is trusted before the next AI
  /// request reads it again. Short, so a moved tunnel reaches running apps
  /// within a minute; a failed request also discards it straight away.
  static const _remoteMaxAge = Duration(minutes: 1);

  static String? _override;
  static String? _remote;
  static DateTime? _remoteFetchedAt;

  static String get baseUrl {
    final saved = _override;
    if (saved != null && saved.isNotEmpty) return saved;
    final remote = _remote;
    if (remote != null && remote.isNotEmpty) return remote;
    if (_fromBuild.isNotEmpty) return normalize(_fromBuild) ?? placeholder;
    return placeholder;
  }

  static bool get isConfigured => baseUrl != placeholder;
  static bool get hasDeviceOverride => _override != null;

  /// Call once in main() before runApp, next to ThemeController.loadSaved().
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _override = prefs.getString(_prefsKey);
  }

  /// Reads ai_base_url from app_config unless the last read is still fresh.
  /// Needs a signed-in session, since anon can't read the table. Never
  /// throws: on any failure the previous value, or the build value, stands.
  static Future<void> refreshRemote() async {
    final fetchedAt = _remoteFetchedAt;
    if (fetchedAt != null && DateTime.now().difference(fetchedAt) < _remoteMaxAge) return;
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentSession == null) return;
      final row = await client.from('app_config').select('value').eq('key', _remoteKey).maybeSingle();
      _remote = normalize(row?['value'] as String?);
      _remoteFetchedAt = DateTime.now();
    } catch (_) {
      // Offline, or a database without migration 035: fall through.
    }
  }

  /// Makes the next [refreshRemote] read the database again, e.g. after a
  /// request to the current address failed because the tunnel moved.
  static void invalidateRemote() => _remoteFetchedAt = null;

  /// Saves an address on this device. Null or blank clears it, falling back
  /// to app_config and then the build-time value.
  static Future<void> setOverride(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = normalize(url);
    _override = cleaned;
    if (cleaned == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, cleaned);
    }
  }

  /// "abc.ngrok-free.app/" -> "https://abc.ngrok-free.app". Paths are joined
  /// as '$baseUrl/api/...', so a trailing slash would produce '//api'.
  static String? normalize(String? url) {
    if (url == null) return null;
    var value = url.trim();
    if (value.isEmpty) return null;
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'https://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}

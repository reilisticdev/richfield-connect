// mobile/lib/config/ai_config.dart
//
// Where the app finds the Python/Flask AI microservice (ai/app.py — CV
// parsing, skill suggestions and the onboarding chat).
//
// UNLIKE supabase_config.dart, this address is NOT stable. The service runs
// behind a free-tier ngrok tunnel whose URL changes every time the tunnel
// restarts, so a URL committed to git is stale by the time anyone else pulls
// it, and rebuilding the APK just to change it costs minutes on demo day.
// Resolution order, first non-empty value wins:
//
//   1. An address saved on the device from the assistant's
//      "AI server address" dialog (SharedPreferences). Fixes a rotated
//      tunnel in seconds, no rebuild.
//   2. --dart-define=AI_BASE_URL=https://<tunnel> passed to flutter run /
//      flutter build.
//   3. [placeholder], which fails with a clear message instead of quietly
//      pointing at somebody's dead tunnel.
//
// Check an address is live with:  curl <url>/health
// It should return {"status":"ok","gemini_configured":true,...}.

import 'package:shared_preferences/shared_preferences.dart';

class AiConfig {
  AiConfig._();

  static const placeholder = 'https://REPLACE-WITH-CURRENT-NGROK-URL.ngrok-free.app';
  static const _fromBuild = String.fromEnvironment('AI_BASE_URL');
  static const _prefsKey = 'richfield_ai_base_url';

  static String? _override;

  static String get baseUrl {
    final saved = _override;
    if (saved != null && saved.isNotEmpty) return saved;
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

  /// Saves an address on this device. Null or blank clears it, falling back
  /// to the build-time value.
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

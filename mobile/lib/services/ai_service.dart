// mobile/lib/services/ai_service.dart
//
// Client for the Python/Flask AI microservice (ai/app.py, PR #18 — built,
// tested with a real Gemini key, merged 2026-09-09). This is deliberately
// NOT a Supabase Edge Function calling an LLM directly — that architecture
// was proposed and explicitly superseded on the team's own task board in
// favor of this standalone service. Building a second backend here would
// duplicate already-tested work; this file just calls the one that exists.
//
// The service is stateless toward Supabase — it doesn't fetch a caller's
// profile itself, it expects the client to send it. Callers pass
// ProfileContext.toAssistantJson() rather than the raw profiles row: that
// row carries email, fcm_token and the pgvector embedding, none of which a
// language model needs.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/ai_config.dart';

/// Thrown for anything we can turn into a message worth showing the user
/// — a non-2xx response with a real `error` field from the Flask service,
/// a timeout, or a connection failure. Kept distinct from a bare Exception
/// so call sites can show `e.message` directly without re-parsing.
class AiServiceException implements Exception {
  AiServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One line of a conversation, replayed to /api/chat so follow-up questions
/// have the context of the earlier answers.
class AiChatTurn {
  const AiChatTurn({required this.fromUser, required this.text});

  final bool fromUser;
  final String text;

  Map<String, dynamic> toJson() => {'role': fromUser ? 'user' : 'assistant', 'text': text};
}

class SkillSuggestions {
  const SkillSuggestions({required this.skills, required this.reason});

  final List<String> skills;
  final String reason;
}

class AiService {
  /// Omit [_baseUrlOverride] to use whatever AiConfig resolves at call time,
  /// so an address changed from inside the app takes effect immediately.
  AiService([this._baseUrlOverride]);

  final String? _baseUrlOverride;

  String get _baseUrl => _baseUrlOverride ?? AiConfig.baseUrl;

  /// Generous but bounded — Gemini generation plus a cold ngrok/Flask
  /// round trip can genuinely take several seconds; this stops a dead
  /// tunnel from hanging a screen forever instead of surfacing an error.
  static const _timeout = Duration(seconds: 30);

  /// ngrok's free tier occasionally serves an HTML interstitial warning
  /// page instead of proxying the request straight through. This header
  /// skips it. Harmless no-op against any other host.
  static const _headers = {
    'Content-Type': 'application/json',
    'ngrok-skip-browser-warning': 'true',
  };

  /// POSTs `cv_text` to /api/parse-cv and returns the parsed fields:
  /// {first_name, last_name, professional_headline, skills: [...],
  /// education_summary}. Only first_name/last_name/professional_headline
  /// map onto real `profiles` columns — skills need one insert per entry
  /// into the separate `skills` table, and education_summary currently
  /// has no structured destination at all. Callers must not blindly
  /// forward this map into a single profiles update.
  Future<Map<String, dynamic>> parseCv(String cvText) {
    return _post('/api/parse-cv', {'cv_text': cvText});
  }

  /// POSTs {message, user_profile, history, mode} to /api/chat and returns
  /// the plain-text reply. [history] is the conversation so far, oldest
  /// first, NOT including [message]. [onboarding] switches the service into
  /// guided setup: one missing profile section per reply.
  Future<String> chat({
    required String message,
    required Map<String, dynamic> profile,
    List<AiChatTurn> history = const [],
    bool onboarding = false,
  }) async {
    final body = await _post('/api/chat', {
      'message': message,
      'user_profile': profile,
      if (history.isNotEmpty) 'history': history.map((t) => t.toJson()).toList(),
      if (onboarding) 'mode': 'onboarding',
    });
    final reply = body['reply'];
    if (reply is! String) {
      throw AiServiceException('The assistant returned an unexpected response shape.');
    }
    return reply;
  }

  /// POSTs the profile to /api/suggest-skills. The service returns
  /// schema-enforced JSON and strips anything already on the profile, so
  /// every name here is safe to offer as "add to my profile".
  Future<SkillSuggestions> suggestSkills({required Map<String, dynamic> profile}) async {
    final body = await _post('/api/suggest-skills', {'user_profile': profile});
    final skills = body['skills'];
    if (skills is! List) {
      throw AiServiceException('The assistant returned an unexpected response shape.');
    }
    return SkillSuggestions(
      skills: skills.whereType<String>().toList(),
      reason: body['reason'] as String? ?? '',
    );
  }

  /// GET /health on [baseUrl] — the address being tried, not the saved one
  /// — so a new tunnel URL can be checked before it replaces a working one.
  static Future<bool> isHealthy(String baseUrl) async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/health'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return false;
      final decoded = jsonDecode(res.body);
      return decoded is Map && decoded['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> payload) async {
    if (_baseUrlOverride == null && !AiConfig.isConfigured) {
      throw AiServiceException(
        'The AI server address hasn\'t been set. Add it under "AI server address".',
      );
    }

    http.Response res;
    try {
      res = await http
          .post(Uri.parse('$_baseUrl$path'), headers: _headers, body: jsonEncode(payload))
          .timeout(_timeout);
    } on TimeoutException {
      throw AiServiceException(
        'The AI assistant took too long to respond. It may be offline — try again in a moment.',
      );
    } catch (e) {
      // Covers SocketException (host unreachable / DNS failure / tunnel
      // dead) and anything else http.post itself can throw. Deliberately
      // broad: every one of these means "couldn't reach the service,"
      // and the user doesn't need the exact Dart exception type to act on it.
      throw AiServiceException(
        'Couldn\'t reach the AI assistant. The server may be offline or its address may have changed.',
      );
    }

    Map<String, dynamic> decoded;
    try {
      final parsed = jsonDecode(res.body);
      if (parsed is! Map<String, dynamic>) {
        throw const FormatException('response body was not a JSON object');
      }
      decoded = parsed;
    } on FormatException {
      // Most common cause: ngrok's interstitial HTML page slipped through
      // despite the skip header, or the tunnel is pointed at the wrong
      // process entirely. A raw HTML blob is not useful to show the user.
      throw AiServiceException(
        'The AI assistant sent back something that wasn\'t valid JSON (HTTP ${res.statusCode}). '
        'The server address may be pointing at the wrong thing.',
      );
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final serverError = decoded['error'];
      throw AiServiceException(
        serverError is String ? serverError : 'AI service error (HTTP ${res.statusCode}).',
      );
    }

    return decoded;
  }
}

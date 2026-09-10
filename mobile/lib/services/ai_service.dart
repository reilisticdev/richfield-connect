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
// profile itself, it expects the client to send it. So every chat() call
// here takes the profile Map the caller already has (e.g. from
// ProfileService.fetchProfile()) rather than a bare user id.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

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

class AiService {
  AiService(this._baseUrl);

  final String _baseUrl;

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
  Future<Map<String, dynamic>> parseCv(String cvText) async {
    final body = await _post('/api/parse-cv', {'cv_text': cvText});
    return body;
  }

  /// POSTs {message, user_profile} to /api/chat and returns the plain-text
  /// reply. `profile` should be whatever ProfileService.fetchProfile()
  /// returned for the current user — the server injects it into the
  /// system prompt so replies are actually specific to this person,
  /// rather than generic (see SYSTEM_PROMPT in ai/app.py).
  Future<String> chat({required String message, required Map<String, dynamic> profile}) async {
    final body = await _post('/api/chat', {'message': message, 'user_profile': profile});
    final reply = body['reply'];
    if (reply is! String) {
      throw AiServiceException('The assistant returned an unexpected response shape.');
    }
    return reply;
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> payload) async {
    http.Response res;
    try {
      res = await http
          .post(Uri.parse('$_baseUrl$path'), headers: _headers, body: jsonEncode(payload))
          .timeout(_timeout);
    } on TimeoutException {
      throw AiServiceException(
        'The AI assistant took too long to respond. It may be offline — check the tunnel is still running.',
      );
    } catch (e) {
      // Covers SocketException (host unreachable / DNS failure / tunnel
      // dead) and anything else http.post itself can throw. Deliberately
      // broad: every one of these means "couldn't reach the service,"
      // and the user doesn't need the exact Dart exception type to act on it.
      throw AiServiceException(
        'Couldn\'t reach the AI assistant. Confirm AiConfig.baseUrl still points at a live tunnel.',
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
        'The tunnel may be pointed at the wrong thing.',
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

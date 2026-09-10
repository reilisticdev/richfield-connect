// mobile/lib/config/ai_config.dart
//
// Base URL for the Python/Flask AI microservice (ai/app.py — CV parsing +
// onboarding chat, POST /api/parse-cv and POST /api/chat). Same pattern as
// config/supabase_config.dart: one obvious place to hold a connection
// endpoint, not buried inside the service class that uses it.
//
// UNLIKE supabase_config.dart, this value is NOT stable. It's a free-tier
// ngrok tunnel — the URL changes every time the tunnel restarts. Before
// blaming AiService for a failure, check this is still the live URL:
//
//     curl <url>/health
//
// should return {"status":"ok","gemini_configured":true,...}. If it
// doesn't (connection refused, or a different tunnel entirely), update
// baseUrl below — that is the fix, not a code change.

class AiConfig {
  AiConfig._();

  static const String baseUrl = 'https://REPLACE-WITH-CURRENT-NGROK-URL.ngrok-free.app';
}

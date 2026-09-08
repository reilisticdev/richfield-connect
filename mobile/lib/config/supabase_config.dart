// mobile/lib/config/supabase_config.dart
//
// Checked-in on purpose: this is the anon/publishable key, which is meant
// to ship inside client binaries (RLS is the real access boundary, not
// secrecy of this value). Matches web/.env.local's VITE_SUPABASE_* pair
// so both clients talk to the same project. Never put the service_role
// key here or anywhere in mobile/.

class SupabaseConfig {
  SupabaseConfig._();

  static const String url = 'https://omyagiwmdabalxifyoth.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9teWFnaXdtZGFiYWx4aWZ5b3RoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc5MzAwMTYsImV4cCI6MjEwMzUwNjAxNn0.9T7k5lFbc6x_gyeDvSAhYNEo2yzgMLwxWJ4un6OigII';
}

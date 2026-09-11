// mobile/lib/services/profile_service.dart
//
// Reads and writes the caller's own `profiles` row. This is the backing
// service for the Portfolio screen's "Edit Details" button, the profile
// picture, and the external links row — all three of which previously had
// no service to call.
//
// THE SILENT-FAILURE TRAP, documented because it bit this project already:
//
//     await client.from('profiles').update(patch).eq('id', userId);
//
// That statement succeeds with NO exception even when RLS matched zero
// rows. PostgREST reports "0 rows updated", supabase_flutter treats that as
// fine, and the UI cheerfully shows "Saved" while the database is unchanged.
// Appending `.select().single()` turns a silent no-op into a real
// PostgrestException (PGRST116), which AuthErrorMapper can then surface.
// Every write in this file uses that pattern.

import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  ProfileService(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>> fetchProfile(String userId) async {
    return await _client.from('profiles').select().eq('id', userId).single();
  }

  /// Patch-style update: only non-null arguments are written, so a screen
  /// that edits three fields cannot blank out the other eight by omission.
  ///
  /// An empty string is meaningful and becomes SQL NULL — that is how a
  /// user clears a link they no longer want on their profile.
  Future<Map<String, dynamic>> updateOwnProfile({
    required String userId,
    String? firstName,
    String? lastName,
    String? professionalHeadline,
    String? careerInterests,
    String? bio,
    String? githubUrl,
    String? linkedinUrl,
    String? websiteUrl,
    String? avatarPath,
  }) async {
    final patch = <String, dynamic>{};

    void putText(String column, String? value) {
      if (value == null) return;
      final trimmed = value.trim();
      patch[column] = trimmed.isEmpty ? null : trimmed;
    }

    void putUrl(String column, String? value) {
      if (value == null) return;
      final trimmed = value.trim();
      patch[column] = trimmed.isEmpty ? null : normalizeUrl(trimmed);
    }

    putText('first_name', firstName);
    putText('last_name', lastName);
    putText('professional_headline', professionalHeadline);
    putText('career_interests', careerInterests);
    putText('bio', bio);
    putText('avatar_path', avatarPath);
    putUrl('github_url', githubUrl);
    putUrl('linkedin_url', linkedinUrl);
    putUrl('website_url', websiteUrl);

    if (patch.isEmpty) return fetchProfile(userId);

    // .select().single() is load-bearing — see the header comment.
    return await _client
        .from('profiles')
        .update(patch)
        .eq('id', userId)
        .select()
        .single();
  }

  /// Adds the skills the user doesn't already list and returns the names
  /// actually inserted. Matching is case-insensitive: the CV parser and the
  /// skill suggester produce "Sql" as readily as "SQL", and `skills` has no
  /// unique constraint on (profile_id, skill_name), so without this an
  /// import run twice would list every skill twice.
  Future<List<String>> addSkills({
    required String userId,
    required Iterable<String> names,
  }) async {
    final existing = await _client.from('skills').select('skill_name').eq('profile_id', userId);
    final have = List<Map<String, dynamic>>.from(existing as List)
        .map((r) => ((r['skill_name'] as String?) ?? '').trim().toLowerCase())
        .toSet();

    final toAdd = <String>[];
    for (final raw in names) {
      final name = raw.trim();
      if (name.isEmpty || !have.add(name.toLowerCase())) continue;
      toAdd.add(name);
    }
    if (toAdd.isEmpty) return toAdd;

    await _client
        .from('skills')
        .insert([for (final name in toAdd) {'profile_id': userId, 'skill_name': name}]);
    return toAdd;
  }

  /// Users type "github.com/me" far more often than they type a full URL.
  /// Storing it bare means url_launcher gets a relative string and silently
  /// refuses to open it, which reads as another dead button.
  static String normalizeUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return value;
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    return 'https://$value';
  }

  /// Returns a message when the value is present but unusable, null when it
  /// is fine or empty. Used by the edit form so a bad link is caught before
  /// the round trip rather than becoming an unopenable link later.
  static String? validateOptionalUrl(String? raw, String label) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parsed = Uri.tryParse(normalizeUrl(raw));
    if (parsed == null || parsed.host.isEmpty || !parsed.host.contains('.')) {
      return 'That $label link doesn\'t look like a valid web address.';
    }
    return null;
  }
}

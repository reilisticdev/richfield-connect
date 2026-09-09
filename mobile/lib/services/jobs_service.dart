// mobile/lib/services/jobs_service.dart
//
// Mirrors AuthService's style: constructor-injected SupabaseClient, returns
// raw Map/List<Map> rows (same as AuthService.fetchOwnProfile() — no
// bespoke model classes), lets PostgrestException propagate for the caller
// to map with AuthErrorMapper.

import 'package:supabase_flutter/supabase_flutter.dart';

class JobsService {
  JobsService(this._client);
  final SupabaseClient _client;

  /// Approved opportunities, with the posting business's name/location
  /// embedded via opportunities.business_id -> profiles.id ->
  /// business_profiles.profile_id. Both FK hops are the only FK on their
  /// respective table, so the embed is unambiguous. A business whose
  /// account_status isn't 'active', or that has no business_profiles row,
  /// comes back with a null nested object — callers must fall back.
  Future<List<Map<String, dynamic>>> fetchApprovedOpportunities() async {
    final rows = await _client
        .from('opportunities')
        .select('id, title, description, opportunity_type, required_skills, '
            'programme_filter, status, created_at, '
            'profiles(business_profiles(company_name, location))')
        .eq('status', 'approved')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<void> apply({required String opportunityId, required String studentId}) {
    return _client.from('applications').insert({
      'opportunity_id': opportunityId,
      'student_id': studentId,
    });
  }

  /// Business posts a new opportunity. RLS ("Business manages own
  /// opportunities") lets a business insert its own rows directly - no RPC
  /// needed. Status defaults to 'pending' at the DB level, so this
  /// automatically goes through the existing admin-approval step before
  /// students can see it.
  Future<void> postOpportunity({
    required String businessId,
    required String title,
    required String description,
    required String opportunityType,
    List<String> requiredSkills = const [],
    String? programmeFilter,
  }) {
    return _client.from('opportunities').insert({
      'business_id': businessId,
      'title': title,
      'description': description,
      'opportunity_type': opportunityType,
      'required_skills': requiredSkills,
      'programme_filter': programmeFilter,
    });
  }
}

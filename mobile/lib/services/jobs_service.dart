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

  /// recommend_opportunities() (migration 026) scores approved listings
  /// against the caller's own skills and most recent programme, and returns
  /// which required skills matched so the card can say why. It reads
  /// auth.uid() itself, so there is no profile id to pass — unlike
  /// match_opportunities(), which ranks for whatever id it is given.
  Future<List<Map<String, dynamic>>> fetchRecommendations({int limit = 5}) async {
    final rows = await _client.rpc('recommend_opportunities', params: {'max_results': limit});
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// `cvPath` is the per-application snapshot from
  /// MediaService.snapshotCvForApplication (null when the member has no CV
  /// on file). `.select().single()` so an RLS-rejected insert surfaces as
  /// an exception instead of a silent "Applied" toast.
  Future<void> apply({
    required String opportunityId,
    required String studentId,
    String? cvPath,
  }) async {
    await _client
        .from('applications')
        .insert({
          'opportunity_id': opportunityId,
          'student_id': studentId,
          if (cvPath != null) 'cv_path': cvPath,
        })
        .select('id')
        .single();
  }

  /// Applicants to one of the caller's own opportunities, newest first.
  /// RLS ("Business views applicants to own opportunities" on
  /// applications, "Authenticated users can view active profiles" on
  /// profiles) scopes this to the caller's own listing with no extra
  /// filtering needed client-side. student_id is the only FK from
  /// applications -> profiles, so the embed is unambiguous (same
  /// reasoning as the business_profiles embed above). A null nested
  /// profiles map means the applicant's account is no longer 'active' -
  /// callers must fall back, not assume it's always present.
  Future<List<Map<String, dynamic>>> fetchApplicants({required String opportunityId}) async {
    final rows = await _client
        .from('applications')
        .select('student_id, status, applied_at, cv_path, '
            'profiles(first_name, last_name, professional_headline)')
        .eq('opportunity_id', opportunityId)
        .order('applied_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
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

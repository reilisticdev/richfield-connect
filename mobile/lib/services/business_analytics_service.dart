// mobile/lib/services/business_analytics_service.dart
//
// All three RPCs are SECURITY DEFINER and internally scope to
// business_id = auth.uid() — no filter params needed client-side.

import 'package:supabase_flutter/supabase_flutter.dart';

class BusinessAnalyticsService {
  BusinessAnalyticsService(this._client);
  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> fetchApplicantPipeline() async {
    final rows = await _client.rpc('get_business_applicant_pipeline');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<List<Map<String, dynamic>>> fetchSkillDistribution() async {
    final rows = await _client.rpc('get_business_candidate_skill_distribution');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<List<Map<String, dynamic>>> fetchListingEngagement() async {
    final rows = await _client.rpc('get_business_listing_engagement');
    return List<Map<String, dynamic>>.from(rows as List);
  }
}

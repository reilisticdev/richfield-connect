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

  /// get_business_listing_engagement() returns every one of the caller's
  /// own opportunities regardless of status - it doesn't even select
  /// `status` - so a rejected (or still-pending) listing showed up here
  /// with harmless-looking zeros forever (Keshav, 2026-09-14: a rejected
  /// "Bonny blues IT support" listing kept appearing as "0/0 views · 0%").
  /// Engagement is only meaningful for a listing students can actually see,
  /// so this fetches each opportunity's current status separately (RLS
  /// already scopes `opportunities` to the caller's own rows the same way
  /// the RPC does) and keeps only the approved ones.
  Future<List<Map<String, dynamic>>> fetchListingEngagement() async {
    final results = await Future.wait<Object>([
      _client.rpc('get_business_listing_engagement'),
      _client.from('opportunities').select('id, status'),
    ]);
    final rows = List<Map<String, dynamic>>.from(results[0] as List);
    final statusById = {
      for (final o in List<Map<String, dynamic>>.from(results[1] as List))
        o['id'] as String: o['status'] as String?,
    };
    return rows.where((row) => statusById[row['opportunity_id']] == 'approved').toList();
  }
}

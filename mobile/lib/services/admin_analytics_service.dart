// mobile/lib/services/admin_analytics_service.dart
//
// The administrator's overview tab on mobile. Uses the same get_admin_* RPCs
// as the web admin console (each raises unless is_admin(auth.uid())), plus a
// count of pending alumni claims, which the "Administrators can view all
// claims" policy on verification_claims allows.
//
// Replaces a StatelessWidget of literals: '12' alumni queue, '3,420'
// students, a 'Vodacom Enterprise Dev' approval whose Authorize button only
// showed a snackbar, and four "Integration Hookpoints" whose Attach buttons
// attached nothing.

import 'package:supabase_flutter/supabase_flutter.dart';

class AdminOverview {
  const AdminOverview({
    required this.usersByRole,
    required this.businessesByStatus,
    required this.flaggedContent,
    required this.monthlyActiveUsers,
    required this.posts,
    required this.videos,
    required this.opportunities,
    required this.pendingAlumniClaims,
  });

  final Map<String, int> usersByRole;
  final Map<String, int> businessesByStatus;
  final int flaggedContent;
  final int monthlyActiveUsers;
  final int posts;
  final int videos;
  final int opportunities;
  final int pendingAlumniClaims;
}

class AdminAnalyticsService {
  AdminAnalyticsService(this._client);

  final SupabaseClient _client;

  Future<AdminOverview> load() async {
    final results = await Future.wait<dynamic>([
      _client.rpc('get_admin_user_counts'),
      _client.rpc('get_admin_business_pipeline'),
      _client.rpc('get_admin_flagged_content_count'),
      _client.rpc('get_admin_mau'),
      _client.rpc('get_admin_content_volume'),
      _client.from('verification_claims').select('id').eq('status', 'pending'),
    ]);

    List<Map<String, dynamic>> rows(int i) => List<Map<String, dynamic>>.from(results[i] as List);
    int asInt(Object? v) => (v as num?)?.toInt() ?? 0;
    Map<String, int> totals(int i, String key) => {
          for (final r in rows(i)) '${r[key] ?? 'unknown'}': asInt(r['total']),
        };

    final volume = rows(4).isEmpty ? const <String, dynamic>{} : rows(4).first;

    return AdminOverview(
      usersByRole: totals(0, 'role'),
      businessesByStatus: totals(1, 'status'),
      flaggedContent: asInt(results[2]),
      monthlyActiveUsers: asInt(results[3]),
      posts: asInt(volume['post_count']),
      videos: asInt(volume['video_count']),
      opportunities: asInt(volume['opportunity_count']),
      pendingAlumniClaims: rows(5).length,
    );
  }
}

// mobile/lib/services/student_analytics_service.dart
//
// Backs the Student Analytics screen: profile views, connection growth,
// engagement with the student's posts, profile completeness against their
// programme, and which of their skills businesses search for. All five RPCs
// (migrations 017/018) are SECURITY DEFINER and scope to auth.uid() inside
// the function, so none of them takes a profile id.
//
// The screen used to be a StatelessWidget of literals — '482' profile views,
// '1.4k' engagement, a "chart" whose points alternated on i.isEven, and
// "more complete than 68% of students in your programme" for every account.

import 'package:supabase_flutter/supabase_flutter.dart';

class StudentAnalytics {
  const StudentAnalytics({
    required this.days,
    required this.dailyProfileViews,
    required this.newConnections,
    required this.posts,
    required this.reactions,
    required this.comments,
    required this.myCompleteness,
    required this.programmeAverage,
    required this.searchedSkills,
  });

  final int days;

  /// One entry per calendar day in the window, oldest first, zero-filled —
  /// the RPC only returns days that had at least one view.
  final List<int> dailyProfileViews;
  final int newConnections;
  final int posts;
  final int reactions;
  final int comments;

  /// Percentages (0–100). Null when the student has no education row: the
  /// RPC compares against their programme, and without one there is nothing
  /// to compare with.
  final double? myCompleteness;
  final double? programmeAverage;

  final List<MapEntry<String, int>> searchedSkills;

  int get totalProfileViews => dailyProfileViews.fold(0, (sum, n) => sum + n);
}

class StudentAnalyticsService {
  StudentAnalyticsService(this._client);

  final SupabaseClient _client;

  Future<StudentAnalytics> load({int days = 30}) async {
    final results = await Future.wait<dynamic>([
      _client.rpc('get_student_profile_views', params: {'days': days}),
      _client.rpc('get_student_connection_growth', params: {'days': days}),
      _client.rpc('get_student_engagement'),
      _client.rpc('get_student_completeness'),
      _client.rpc('get_student_top_searched_skills'),
    ]);

    List<Map<String, dynamic>> rows(int i) => List<Map<String, dynamic>>.from(results[i] as List);
    int asInt(Object? v) => (v as num?)?.toInt() ?? 0;
    double? asDouble(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
    final daily = List<int>.filled(days, 0);
    for (final row in rows(0)) {
      final date = DateTime.tryParse(row['view_date'] as String? ?? '');
      if (date == null) continue;
      final index = DateTime(date.year, date.month, date.day).difference(firstDay).inDays;
      if (index >= 0 && index < days) daily[index] += asInt(row['view_count']);
    }

    final engagement = rows(2).isEmpty ? const <String, dynamic>{} : rows(2).first;
    final completeness = rows(3).isEmpty ? const <String, dynamic>{} : rows(3).first;

    return StudentAnalytics(
      days: days,
      dailyProfileViews: daily,
      newConnections: rows(1).fold(0, (sum, r) => sum + asInt(r['connection_count'])),
      posts: asInt(engagement['total_posts']),
      reactions: asInt(engagement['total_reactions']),
      comments: asInt(engagement['total_comments']),
      myCompleteness: asDouble(completeness['my_completeness_pct']),
      programmeAverage: asDouble(completeness['programme_avg_completeness_pct']),
      searchedSkills: [
        for (final r in rows(4))
          if ((r['skill_name'] as String?)?.isNotEmpty ?? false)
            MapEntry(r['skill_name'] as String, asInt(r['search_count'])),
      ],
    );
  }
}

// mobile/lib/services/portfolio_service.dart
//
// The signed-in user's own portfolio for the Portfolio tab: the sections
// they write themselves (education, experience, projects, certifications,
// badges, achievements, leadership roles), what other members have given them (skill endorsements,
// written recommendations) and their connection count — one parallel round
// trip.
//
// Before this the tab rendered MockData for every one of these sections, so
// every account showed the same invented AWS certificate, GitHub repos,
// endorsement counts and lecturer recommendation — and nothing in the app
// could write to any of these tables, so there was no way to replace them.
// Each table has an "Owner manages own rows" RLS policy, so plain inserts and
// deletes are enough; no RPC.
//
// Writes end in .select() for the same reason ProfileService's do: a delete
// that RLS filters to zero rows otherwise "succeeds" without an error.

import 'package:supabase_flutter/supabase_flutter.dart';

enum PortfolioSection { education, experience, projects, certifications, badges, achievements, leadership }

extension PortfolioSectionTable on PortfolioSection {
  String get table => switch (this) {
        PortfolioSection.education => 'education',
        PortfolioSection.experience => 'work_experience',
        PortfolioSection.projects => 'projects',
        PortfolioSection.certifications => 'certifications',
        PortfolioSection.badges => 'badges',
        PortfolioSection.achievements => 'achievements',
        PortfolioSection.leadership => 'leadership_roles',
      };
}

class PortfolioData {
  const PortfolioData({
    this.skills = const [],
    this.endorsements = const [],
    this.education = const [],
    this.experience = const [],
    this.projects = const [],
    this.certifications = const [],
    this.badges = const [],
    this.achievements = const [],
    this.leadership = const [],
    this.recommendations = const [],
    this.connectionCount = 0,
  });

  final List<Map<String, dynamic>> skills;

  /// Endorsements received: {skill_id, endorser_id}.
  final List<Map<String, dynamic>> endorsements;
  final List<Map<String, dynamic>> education;
  final List<Map<String, dynamic>> experience;
  final List<Map<String, dynamic>> projects;
  final List<Map<String, dynamic>> certifications;

  /// Digital badges (Credly, Microsoft Learn, Google, AWS…): {id, title,
  /// issuer, credential_url, date_earned}. Same table shape as certifications.
  final List<Map<String, dynamic>> badges;

  /// Awards, dean's list, competition placings, scholarships (guidelines 2.3
  /// "achievements"): {id, title, description, date_earned}. Table from
  /// migration 010; the section had no UI until 2026-09-12.
  final List<Map<String, dynamic>> achievements;
  final List<Map<String, dynamic>> leadership;

  /// Recommendations received, each with an embedded `author` profile.
  final List<Map<String, dynamic>> recommendations;
  final int connectionCount;

  int endorsementsFor(String skillId) => endorsements.where((e) => e['skill_id'] == skillId).length;
}

class PortfolioService {
  PortfolioService(this._client);

  final SupabaseClient _client;

  Future<PortfolioData> load(String userId) async {
    final results = await Future.wait<dynamic>([
      _client.from('skills').select('id, skill_name').eq('profile_id', userId).order('created_at'),
      _client.from('endorsements').select('skill_id, endorser_id').eq('recipient_id', userId),
      _client
          .from('education')
          .select('id, programme, campus, enrolment_year, graduation_year')
          .eq('profile_id', userId)
          .order('enrolment_year', ascending: false),
      _client
          .from('work_experience')
          .select('id, title, organisation, description, start_date, end_date')
          .eq('profile_id', userId)
          .order('start_date', ascending: false),
      _client
          .from('projects')
          .select('id, title, description, github_url, live_url')
          .eq('profile_id', userId),
      _client
          .from('certifications')
          .select('id, title, issuer, credential_url, date_earned')
          .eq('profile_id', userId)
          .order('date_earned', ascending: false),
      _client
          .from('badges')
          .select('id, title, issuer, credential_url, date_earned')
          .eq('profile_id', userId)
          .order('date_earned', ascending: false),
      _client
          .from('achievements')
          .select('id, title, description, date_earned')
          .eq('profile_id', userId)
          .order('date_earned', ascending: false),
      _client
          .from('leadership_roles')
          .select('id, role_title, organisation, description')
          .eq('profile_id', userId),
      // recommendations has two FKs to profiles, so the embed names one.
      _client
          .from('recommendations')
          .select('id, body, created_at, author_id, '
              'author:profiles!recommendations_author_id_fkey(first_name, last_name, role, '
              'professional_headline, avatar_path)')
          .eq('recipient_id', userId)
          .order('created_at', ascending: false),
      _client
          .from('connections')
          .select('id')
          .eq('status', 'accepted')
          .or('requester_id.eq.$userId,addressee_id.eq.$userId'),
    ]);

    List<Map<String, dynamic>> rows(int i) => List<Map<String, dynamic>>.from(results[i] as List);

    return PortfolioData(
      skills: rows(0),
      endorsements: rows(1),
      education: rows(2),
      experience: rows(3),
      projects: rows(4),
      certifications: rows(5),
      badges: rows(6),
      achievements: rows(7),
      leadership: rows(8),
      recommendations: rows(9),
      connectionCount: rows(10).length,
    );
  }

  Future<void> add(
    PortfolioSection section, {
    required String userId,
    required Map<String, dynamic> values,
  }) async {
    await _client
        .from(section.table)
        .insert({...values, 'profile_id': userId})
        .select('id')
        .single();
  }

  Future<void> remove(PortfolioSection section, String id) async {
    await _client.from(section.table).delete().eq('id', id).select('id').single();
  }
}

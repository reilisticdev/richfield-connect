// mobile/lib/services/career_pathway_service.dart
//
// Data for the career pathway explorer. The career_pathways view (migration
// 031) has one row per alumnus, per programme studied, per role held. It is
// security_invoker, so alumni who hide their education or experience from the
// viewer's role don't come back at all. Rows are grouped here into one
// pathway per alumnus and programme; the screen does the filtering.

import 'package:supabase_flutter/supabase_flutter.dart';

class PathwayRole {
  const PathwayRole({required this.title, required this.organisation, this.industry, this.start, this.end});

  final String title;
  final String organisation;
  final String? industry;
  final DateTime? start;

  /// Null while the alumnus still holds the role.
  final DateTime? end;
}

class AlumniPathway {
  const AlumniPathway({
    required this.alumniId,
    required this.firstName,
    required this.lastName,
    required this.programme,
    required this.roles,
    this.campus,
    this.graduationYear,
    this.headline,
    this.avatarPath,
    this.skills = const [],
  });

  final String alumniId;
  final String firstName;
  final String lastName;
  final String programme;
  final String? campus;
  final int? graduationYear;
  final String? headline;
  final String? avatarPath;

  /// Oldest first, so a card reads as a timeline from graduation onwards.
  final List<PathwayRole> roles;
  final List<String> skills;

  String get name => '$firstName $lastName'.trim();

  AlumniPathway withSkills(List<String> skills) => AlumniPathway(
        alumniId: alumniId,
        firstName: firstName,
        lastName: lastName,
        programme: programme,
        roles: roles,
        campus: campus,
        graduationYear: graduationYear,
        headline: headline,
        avatarPath: avatarPath,
        skills: skills,
      );
}

class CareerPathways {
  const CareerPathways({required this.pathways, this.myProgramme});

  final List<AlumniPathway> pathways;

  /// The viewer's most recent programme, when their education is filled in.
  final String? myProgramme;

  List<String> get programmes => _distinct(pathways.map((p) => p.programme));

  List<String> get industries => _distinct([
        for (final p in pathways)
          for (final r in p.roles)
            if (r.industry != null) r.industry!,
      ]);

  static List<String> _distinct(Iterable<String> values) {
    final byKey = <String, String>{};
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) byKey.putIfAbsent(trimmed.toLowerCase(), () => trimmed);
    }
    return byKey.values.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }
}

class CareerPathwayService {
  CareerPathwayService([SupabaseClient? client]) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  Future<CareerPathways> load() async {
    final userId = _client.auth.currentUser?.id;
    final Future<Map<String, dynamic>?> myEducation = userId == null
        ? Future.value(null)
        : _client
            .from('education')
            .select('programme')
            .eq('profile_id', userId)
            .order('enrolment_year', ascending: false)
            .limit(1)
            .maybeSingle();

    final results = await Future.wait<Object?>([
      _client
          .from('career_pathways')
          .select('programme, alumni_id, first_name, last_name, title, organisation, experience_id, industry, '
              'start_date, end_date, campus, graduation_year, professional_headline, avatar_path')
          .limit(1000),
      myEducation,
    ]);

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in (results[0] as List).cast<Map<String, dynamic>>()) {
      final programme = (row['programme'] as String? ?? '').trim();
      if (programme.isEmpty) continue;
      grouped.putIfAbsent('${row['alumni_id']}|${programme.toLowerCase()}', () => []).add(row);
    }
    final pathways = [for (final rows in grouped.values) _pathwayFrom(rows)];

    final ids = {for (final p in pathways) p.alumniId}.toList();
    final skillsById = <String, List<String>>{};
    if (ids.isNotEmpty) {
      final skillRows = await _client.from('skills').select('profile_id, skill_name').inFilter('profile_id', ids);
      for (final row in skillRows) {
        final name = (row['skill_name'] as String? ?? '').trim();
        if (name.isNotEmpty) skillsById.putIfAbsent(row['profile_id'] as String, () => []).add(name);
      }
    }

    pathways.sort((a, b) {
      final byYear = (b.graduationYear ?? 0).compareTo(a.graduationYear ?? 0);
      return byYear != 0 ? byYear : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    final mine = results[1] as Map<String, dynamic>?;
    return CareerPathways(
      pathways: [for (final p in pathways) p.withSkills(skillsById[p.alumniId] ?? const [])],
      myProgramme: _text(mine?['programme']),
    );
  }

  static AlumniPathway _pathwayFrom(List<Map<String, dynamic>> rows) {
    final first = rows.first;
    final seen = <String>{};
    final roles = <PathwayRole>[];
    // An alumnus with two education rows for one programme repeats each role.
    for (final row in rows) {
      if (!seen.add(row['experience_id'] as String)) continue;
      roles.add(PathwayRole(
        title: (row['title'] as String? ?? '').trim(),
        organisation: (row['organisation'] as String? ?? '').trim(),
        industry: _text(row['industry']),
        start: DateTime.tryParse(row['start_date'] as String? ?? ''),
        end: DateTime.tryParse(row['end_date'] as String? ?? ''),
      ));
    }
    roles.sort((a, b) {
      final sa = a.start;
      final sb = b.start;
      if (sa == null || sb == null) return sa == null ? (sb == null ? 0 : 1) : -1;
      return sa.compareTo(sb);
    });

    return AlumniPathway(
      alumniId: first['alumni_id'] as String,
      firstName: (first['first_name'] as String? ?? '').trim(),
      lastName: (first['last_name'] as String? ?? '').trim(),
      programme: (first['programme'] as String).trim(),
      campus: _text(first['campus']),
      graduationYear: (first['graduation_year'] as num?)?.toInt(),
      headline: _text(first['professional_headline']),
      avatarPath: _text(first['avatar_path']),
      roles: roles,
    );
  }

  static String? _text(Object? value) {
    final s = (value as String?)?.trim();
    return s == null || s.isEmpty ? null : s;
  }
}

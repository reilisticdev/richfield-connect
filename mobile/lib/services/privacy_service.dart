// mobile/lib/services/privacy_service.dart
//
// The signed-in member's POPIA controls: consents (consent_records), who can
// see each portfolio section (profile_visibility), and the export and deletion
// RPCs. Migration 030 is what makes each of these hold server-side.

import 'package:supabase_flutter/supabase_flutter.dart';

import 'media_service.dart';

enum ConsentType { registration, aiProcessing }

extension ConsentTypeKey on ConsentType {
  String get key => switch (this) {
        ConsentType.registration => 'registration',
        ConsentType.aiProcessing => 'ai_processing',
      };
}

class ConsentRecord {
  const ConsentRecord({required this.type, required this.grantedAt, this.withdrawnAt});

  factory ConsentRecord.fromRow(Map<String, dynamic> row) => ConsentRecord(
        type: row['consent_type'] as String,
        grantedAt: DateTime.parse(row['granted_at'] as String).toLocal(),
        withdrawnAt: row['revoked_at'] == null ? null : DateTime.parse(row['revoked_at'] as String).toLocal(),
      );

  final String type;
  final DateTime grantedAt;
  final DateTime? withdrawnAt;

  bool get isActive => withdrawnAt == null;
}

/// Who, besides its owner, can see a portfolio section. Values match
/// profile_visibility.visible_to.
enum Audience { student, alumni, business }

extension AudienceLabel on Audience {
  String get label => switch (this) {
        Audience.student => 'Students',
        Audience.alumni => 'Alumni',
        Audience.business => 'Employers',
      };
}

/// The eight sections whose RLS calls can_view_profile_section().
enum ProfileSection {
  skills,
  education,
  workExperience,
  projects,
  certifications,
  badges,
  achievements,
  leadershipRoles,
}

extension ProfileSectionInfo on ProfileSection {
  String get key => switch (this) {
        ProfileSection.skills => 'skills',
        ProfileSection.education => 'education',
        ProfileSection.workExperience => 'work_experience',
        ProfileSection.projects => 'projects',
        ProfileSection.certifications => 'certifications',
        ProfileSection.badges => 'badges',
        ProfileSection.achievements => 'achievements',
        ProfileSection.leadershipRoles => 'leadership_roles',
      };

  String get label => switch (this) {
        ProfileSection.skills => 'Skills',
        ProfileSection.education => 'Education',
        ProfileSection.workExperience => 'Work experience',
        ProfileSection.projects => 'Projects',
        ProfileSection.certifications => 'Certifications',
        ProfileSection.badges => 'Badges',
        ProfileSection.achievements => 'Achievements',
        ProfileSection.leadershipRoles => 'Leadership roles',
      };
}

class PrivacySettings {
  const PrivacySettings({required this.role, required this.consents, required this.visibility});

  final String? role;

  /// Every consent recorded for this member, newest first.
  final List<ConsentRecord> consents;

  /// Sections with restrictions. A section missing here is visible to all members.
  final Map<ProfileSection, Set<Audience>> visibility;

  bool get isAdministrator => role == 'administrator';

  ConsentRecord? latest(ConsentType type) {
    for (final consent in consents) {
      if (consent.type == type.key) return consent;
    }
    return null;
  }

  Set<Audience> audiencesFor(ProfileSection section) => visibility[section] ?? Audience.values.toSet();

  PrivacySettings withAudiences(ProfileSection section, Set<Audience> audiences) => PrivacySettings(
        role: role,
        consents: consents,
        visibility: {...visibility, section: audiences},
      );
}

class PrivacyService {
  PrivacyService([SupabaseClient? client]) : _clientOverride = client;

  static const verificationDocsBucket = 'alumni-verification-docs';

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Your session has expired. Sign in again.');
    return id;
  }

  Future<PrivacySettings> load() async {
    final userId = _userId;
    final results = await Future.wait<Object?>([
      _client.from('profiles').select('role').eq('id', userId).maybeSingle(),
      _client
          .from('consent_records')
          .select('consent_type, granted_at, revoked_at')
          .eq('profile_id', userId)
          .order('granted_at', ascending: false),
      _client.from('profile_visibility').select('section, visible_to').eq('profile_id', userId),
    ]);

    final profile = results[0] as Map<String, dynamic>?;
    final consents = [
      for (final row in results[1] as List) ConsentRecord.fromRow(row as Map<String, dynamic>),
    ];

    final visibility = <ProfileSection, Set<Audience>>{};
    for (final row in (results[2] as List).cast<Map<String, dynamic>>()) {
      final section = ProfileSection.values.where((s) => s.key == row['section']).firstOrNull;
      if (section == null) continue;
      final audiences = visibility.putIfAbsent(section, () => <Audience>{});
      final visibleTo = row['visible_to'] as String?;
      if (visibleTo == 'public') {
        audiences.addAll(Audience.values);
      } else {
        audiences.addAll(Audience.values.where((a) => a.name == visibleTo));
      }
    }

    return PrivacySettings(role: profile?['role'] as String?, consents: consents, visibility: visibility);
  }

  Future<bool> hasAiConsent() async {
    final rows = await _client
        .from('consent_records')
        .select('consent_type')
        .eq('profile_id', _userId)
        .eq('consent_type', ConsentType.aiProcessing.key)
        .isFilter('revoked_at', null)
        .limit(1);
    return rows.isNotEmpty;
  }

  Future<void> grant(ConsentType type) async {
    try {
      await _client.from('consent_records').insert({'profile_id': _userId, 'consent_type': type.key});
    } on PostgrestException catch (e) {
      // 23505: this consent is already active (one active row per type).
      if (e.code != '23505') rethrow;
    }
  }

  /// The database replaces the timestamp with its own clock (consent_records_guard).
  Future<void> withdraw(ConsentType type) {
    return _client
        .from('consent_records')
        .update({'revoked_at': DateTime.now().toUtc().toIso8601String()})
        .eq('profile_id', _userId)
        .eq('consent_type', type.key)
        .isFilter('revoked_at', null);
  }

  Future<void> setAudiences(ProfileSection section, Set<Audience> audiences) {
    return _client.rpc('set_section_visibility', params: {
      'section_name': section.key,
      'audiences': [for (final a in audiences) a.name],
    });
  }

  Future<Map<String, dynamic>> exportMyData() async {
    final data = await _client.rpc('export_my_data');
    return Map<String, dynamic>.from(data as Map);
  }

  /// Files first, then the account: storage objects aren't linked to
  /// auth.users, so deleting the account alone would leave them behind.
  Future<void> deleteAccount() async {
    final userId = _userId;
    final profile = await _client.from('profiles').select('role').eq('id', userId).maybeSingle();
    if (profile?['role'] == 'administrator') {
      throw const AuthException('Administrator accounts can\'t be deleted from the app.');
    }

    // list() is one level deep, so the per-application CV snapshots in
    // cvs/<uid>/applications/ (migration 039) need their own pass.
    for (final (bucket, folder) in [
      (MediaService.avatarsBucket, userId),
      (MediaService.postMediaBucket, userId),
      (MediaService.cvsBucket, '$userId/applications'),
      (MediaService.cvsBucket, userId),
      (verificationDocsBucket, userId),
    ]) {
      final storage = _client.storage.from(bucket);
      final paths = <String>[];
      for (var offset = 0;; offset += 100) {
        final page = await storage.list(path: folder, searchOptions: SearchOptions(limit: 100, offset: offset));
        paths.addAll([
          for (final file in page)
            if (file.id != null) '$folder/${file.name}',
        ]);
        if (page.length < 100) break;
      }
      if (paths.isNotEmpty) await storage.remove(paths);
    }

    await _client.rpc('delete_my_account');
  }

  /// Local only: the account no longer exists, so there's no server session to revoke.
  Future<void> signOutAfterDeletion() => _client.auth.signOut(scope: SignOutScope.local);
}

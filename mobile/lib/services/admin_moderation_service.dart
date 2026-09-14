// mobile/lib/services/admin_moderation_service.dart
//
// Mobile parity for the moderation actions the web admin console already
// has (Moderation.jsx / Users.jsx / Opportunities.jsx): approve/reject a
// pending business or opportunity listing, suspend/reactivate/remove a
// member. The RPCs here already self-check is_admin(auth.uid()) and already
// log to account_actions / verification_audit; the opportunity status
// update relies on the "Administrators manage all opportunities" RLS policy
// instead, exactly like the web console does - this file only calls what's
// already live, same as AdminAnalyticsService does for the read side.

import 'package:supabase_flutter/supabase_flutter.dart';

class AdminMemberRow {
  const AdminMemberRow({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
    required this.accountStatus,
    this.companyName,
  });

  factory AdminMemberRow.fromRow(Map<String, dynamic> row) {
    final businessProfile = row['business_profiles'];
    String? companyName;
    if (businessProfile is Map<String, dynamic>) {
      companyName = businessProfile['company_name'] as String?;
    } else if (businessProfile is List && businessProfile.isNotEmpty) {
      companyName = (businessProfile.first as Map<String, dynamic>?)?['company_name'] as String?;
    }
    return AdminMemberRow(
      id: row['id'] as String,
      firstName: (row['first_name'] as String?) ?? '',
      lastName: (row['last_name'] as String?) ?? '',
      email: (row['email'] as String?) ?? '',
      role: (row['role'] as String?) ?? 'student',
      accountStatus: (row['account_status'] as String?) ?? 'active',
      companyName: companyName,
    );
  }

  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String role;
  final String accountStatus;
  final String? companyName;

  String get fullName {
    final name = '$firstName $lastName'.trim();
    return name.isEmpty ? 'Unnamed member' : name;
  }
}

class AdminOpportunityRow {
  const AdminOpportunityRow({
    required this.id,
    required this.title,
    required this.companyName,
  });

  factory AdminOpportunityRow.fromRow(Map<String, dynamic> row) {
    final businessProfile = (row['profiles'] as Map<String, dynamic>?)?['business_profiles'];
    return AdminOpportunityRow(
      id: row['id'] as String,
      title: (row['title'] as String?) ?? 'Untitled opportunity',
      companyName: (businessProfile as Map<String, dynamic>?)?['company_name'] as String?,
    );
  }

  final String id;
  final String title;
  final String? companyName;
}

/// A pending content_reports row joined with the reporter and the reported
/// post/comment, mirroring the web console's Moderation.jsx "Flagged
/// Content" section. [targetBody] is null when the content was already
/// deleted by the time the queue loads (someone else's report, or the
/// author deleted it themselves).
class FlaggedContentRow {
  const FlaggedContentRow({
    required this.reportId,
    required this.contentId,
    required this.contentType,
    required this.reason,
    required this.reporterName,
    this.targetBody,
    this.targetAuthorName,
  });

  final String reportId;
  final String contentId;

  /// One of content_reports' allowed types: post, video or comment.
  final String contentType;
  final String reason;
  final String reporterName;
  final String? targetBody;
  final String? targetAuthorName;

  String get contentLabel => contentType == 'comment'
      ? 'Comment'
      : contentType == 'video'
          ? 'Video post'
          : 'Post';
}

class AdminModerationService {
  AdminModerationService(this._client);

  final SupabaseClient _client;

  /// admin_profiles (migration 037) is the only read path that still
  /// carries email, and it's postgres-owned + is_admin()-gated - the same
  /// table the web console reads for Users.jsx and Moderation.jsx.
  static const _memberFields =
      'id, first_name, last_name, email, role, account_status, business_profiles(company_name)';

  /// Every non-administrator account, newest first. Administrators are
  /// left out here rather than shown disabled: admin_remove_account and
  /// admin_set_account_status both refuse to act on an administrator row,
  /// so there is no working action to offer for one anyway.
  Future<List<AdminMemberRow>> fetchMembers() async {
    final rows = await _client
        .from('admin_profiles')
        .select(_memberFields)
        .neq('role', 'administrator')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List)
        .map(AdminMemberRow.fromRow)
        .toList();
  }

  Future<List<AdminMemberRow>> fetchPendingBusinesses() async {
    final rows = await _client
        .from('admin_profiles')
        .select(_memberFields)
        .eq('role', 'business')
        .eq('account_status', 'pending');
    return List<Map<String, dynamic>>.from(rows as List)
        .map(AdminMemberRow.fromRow)
        .toList();
  }

  Future<void> approveBusiness(String businessId) async {
    await _client.rpc('approve_business_account', params: {'target_business_id': businessId});
  }

  Future<void> rejectBusiness(String businessId, String? reason) async {
    await _client.rpc(
      'reject_business_account',
      params: {'target_business_id': businessId, 'reason': reason},
    );
  }

  /// business_id is the only FK from opportunities to profiles, so this
  /// embed is unambiguous - same reasoning as JobsService's own listings.
  static const _opportunityFields = 'id, title, profiles(business_profiles(company_name))';

  Future<List<AdminOpportunityRow>> fetchPendingOpportunities() async {
    final rows = await _client
        .from('opportunities')
        .select(_opportunityFields)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List)
        .map(AdminOpportunityRow.fromRow)
        .toList();
  }

  /// There is no approve/reject_opportunity RPC - the web console
  /// (Opportunities.jsx) updates `status` directly, relying on the
  /// "Administrators manage all opportunities" RLS policy (an ALL policy,
  /// not just SELECT). This mirrors that exactly. `.select('id')` catches
  /// an RLS-silent-empty-result the same way FeedService.deletePost() does.
  Future<void> _setOpportunityStatus(String opportunityId, String status) async {
    final rows = await _client
        .from('opportunities')
        .update({'status': status})
        .eq('id', opportunityId)
        .select('id');
    if (List<Map<String, dynamic>>.from(rows as List).isEmpty) {
      throw const PostgrestException(message: 'That listing could not be updated.');
    }
  }

  Future<void> approveOpportunity(String opportunityId) =>
      _setOpportunityStatus(opportunityId, 'approved');

  Future<void> rejectOpportunity(String opportunityId) =>
      _setOpportunityStatus(opportunityId, 'rejected');

  Future<void> setSuspended(String memberId, bool suspend, String? reason) async {
    await _client.rpc(
      'admin_set_account_status',
      params: {'target_id': memberId, 'suspend': suspend, 'reason': reason},
    );
  }

  /// Deletes the auth user, the profile row and everything that cascades
  /// from it (posts, comments, connections, messages, applications). There
  /// is no undo - the caller must confirm before calling this.
  Future<void> removeAccount(String memberId, String? reason) async {
    await _client.rpc('admin_remove_account', params: {'target_id': memberId, 'reason': reason});
  }

  /// Every pending report, oldest first, same ordering as the web console.
  /// `profiles(first_name, last_name)` is the reporter, readable under the
  /// column-privacy grant from migration 037 the same way admin_profiles is.
  static const _reportFields =
      'id, content_id, content_type, reason, profiles(first_name, last_name)';

  Future<List<FlaggedContentRow>> fetchFlaggedContent() async {
    final reportRows = await _client
        .from('content_reports')
        .select(_reportFields)
        .eq('status', 'pending')
        .order('created_at', ascending: true);
    final reports = List<Map<String, dynamic>>.from(reportRows as List);
    if (reports.isEmpty) return [];

    final postIds = reports
        .where((r) => r['content_type'] != 'comment')
        .map((r) => r['content_id'] as String)
        .toList();
    final commentIds = reports
        .where((r) => r['content_type'] == 'comment')
        .map((r) => r['content_id'] as String)
        .toList();

    final targets = <String, Map<String, dynamic>>{};
    const targetFields = 'id, body, profiles(first_name, last_name)';
    if (postIds.isNotEmpty) {
      final rows = await _client.from('posts').select(targetFields).inFilter('id', postIds);
      for (final row in List<Map<String, dynamic>>.from(rows as List)) {
        targets[row['id'] as String] = row;
      }
    }
    if (commentIds.isNotEmpty) {
      final rows = await _client.from('comments').select(targetFields).inFilter('id', commentIds);
      for (final row in List<Map<String, dynamic>>.from(rows as List)) {
        targets[row['id'] as String] = row;
      }
    }

    String? nameFrom(Map<String, dynamic>? profile) {
      if (profile == null) return null;
      final name = '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim();
      return name.isEmpty ? null : name;
    }

    return reports.map((report) {
      final target = targets[report['content_id'] as String];
      final reporterProfile = report['profiles'] as Map<String, dynamic>?;
      final targetProfile = target?['profiles'] as Map<String, dynamic>?;
      return FlaggedContentRow(
        reportId: report['id'] as String,
        contentId: report['content_id'] as String,
        contentType: report['content_type'] as String,
        reason: report['reason'] as String,
        reporterName: nameFrom(reporterProfile) ?? 'Unknown user',
        targetBody: target?['body'] as String?,
        targetAuthorName: nameFrom(targetProfile),
      );
    }).toList();
  }

  /// Closes every pending report about the same content item, not just the
  /// one row the admin tapped - mirrors Moderation.jsx's closeReports.
  Future<void> closeReports(String contentId, String status) async {
    await _client
        .from('content_reports')
        .update({'status': status})
        .eq('content_id', contentId)
        .eq('status', 'pending');
  }
}

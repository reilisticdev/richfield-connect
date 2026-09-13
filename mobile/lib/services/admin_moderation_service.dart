// mobile/lib/services/admin_moderation_service.dart
//
// Mobile parity for the moderation actions the web admin console already
// has (Moderation.jsx / Users.jsx): approve/reject a pending business,
// suspend/reactivate/remove a member. Every RPC here already self-checks
// is_admin(auth.uid()) and already logs to account_actions /
// verification_audit - this file only calls what's already live, same as
// AdminAnalyticsService does for the read side.

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
}

// mobile/lib/screens/admin_moderation_screen.dart
//
// Mobile parity for the web-only moderation actions Keshav flagged as a gap
// (2026-09-13 audit, extended 2026-09-14): approve/reject a pending
// business, approve/reject a pending opportunity listing, and
// suspend/reactivate/remove a member. (Deleting a post is wired straight
// into the Feed tab's existing ••• menu instead, since that's where
// FeedService.deletePost() and the "Author manages own posts, plus
// administrators" RLS policy already apply.) Every action here calls
// something that already exists and already self-checks is_admin() - see
// AdminModerationService.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart'
    show AppColors, AppRadius, AppSpace, AppText, InitialsAvatar, RichfieldHeader, RoundedCard,
        SectionHeader;
import '../services/admin_moderation_service.dart';
import '../services/auth_error_mapper.dart';

class AdminModerationScreen extends StatefulWidget {
  const AdminModerationScreen({super.key});

  @override
  State<AdminModerationScreen> createState() => _AdminModerationScreenState();
}

class _AdminModerationScreenState extends State<AdminModerationScreen> {
  final _service = AdminModerationService(Supabase.instance.client);

  bool _loading = true;
  String? _error;
  List<AdminMemberRow> _pendingBusinesses = [];
  List<AdminOpportunityRow> _pendingOpportunities = [];
  List<AdminMemberRow> _members = [];

  String _search = '';
  String _statusFilter = 'all';
  static const _statuses = ['all', 'active', 'pending', 'suspended', 'rejected'];

  /// id currently mid-action, so its row can show a spinner and every
  /// button on the screen can be disabled to stop a double-tap.
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        _service.fetchPendingBusinesses(),
        _service.fetchPendingOpportunities(),
        _service.fetchMembers(),
      ]);
      if (!mounted) return;
      setState(() {
        _pendingBusinesses = results[0] as List<AdminMemberRow>;
        _pendingOpportunities = results[1] as List<AdminOpportunityRow>;
        _members = results[2] as List<AdminMemberRow>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AuthErrorMapper.fromAny(e);
        _loading = false;
      });
    }
  }

  List<AdminMemberRow> get _visibleMembers {
    final query = _search.trim().toLowerCase();
    return _members.where((member) {
      final matchesStatus = _statusFilter == 'all' || member.accountStatus == _statusFilter;
      final matchesQuery = query.isEmpty ||
          member.fullName.toLowerCase().contains(query) ||
          member.email.toLowerCase().contains(query);
      return matchesStatus && matchesQuery;
    }).toList();
  }

  Future<void> _approveBusiness(AdminMemberRow business) async {
    setState(() => _busyId = business.id);
    try {
      await _service.approveBusiness(business.id);
      if (!mounted) return;
      setState(() {
        _pendingBusinesses = _pendingBusinesses.where((b) => b.id != business.id).toList();
        _busyId = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${business.companyName ?? business.fullName} approved.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthErrorMapper.fromAny(e))));
    }
  }

  Future<void> _rejectBusiness(AdminMemberRow business) async {
    final reason = await _promptReason(
      title: 'Reject ${business.companyName ?? business.fullName}?',
      message: "This listing won't appear in the business directory. Members who applied see nothing further.",
      confirmLabel: 'Reject listing',
    );
    if (reason == null) return;

    setState(() => _busyId = business.id);
    try {
      await _service.rejectBusiness(business.id, reason.isEmpty ? null : reason);
      if (!mounted) return;
      setState(() {
        _pendingBusinesses = _pendingBusinesses.where((b) => b.id != business.id).toList();
        _busyId = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${business.companyName ?? business.fullName} rejected.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthErrorMapper.fromAny(e))));
    }
  }

  Future<void> _approveOpportunity(AdminOpportunityRow opportunity) async {
    setState(() => _busyId = opportunity.id);
    try {
      await _service.approveOpportunity(opportunity.id);
      if (!mounted) return;
      setState(() {
        _pendingOpportunities = _pendingOpportunities.where((o) => o.id != opportunity.id).toList();
        _busyId = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('"${opportunity.title}" approved.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthErrorMapper.fromAny(e))));
    }
  }

  Future<void> _rejectOpportunity(AdminOpportunityRow opportunity) async {
    final confirmed = await _confirm(
      title: 'Reject "${opportunity.title}"?',
      message: "It won't be shown to students. The posting business can submit a revised listing.",
      confirmLabel: 'Reject listing',
      destructive: true,
    );
    if (!confirmed) return;

    setState(() => _busyId = opportunity.id);
    try {
      await _service.rejectOpportunity(opportunity.id);
      if (!mounted) return;
      setState(() {
        _pendingOpportunities = _pendingOpportunities.where((o) => o.id != opportunity.id).toList();
        _busyId = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('"${opportunity.title}" rejected.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthErrorMapper.fromAny(e))));
    }
  }

  Future<void> _suspend(AdminMemberRow member) async {
    final reason = await _promptReason(
      title: 'Suspend ${member.fullName}?',
      message: "They're signed out immediately and can't sign in until reactivated.",
      confirmLabel: 'Suspend',
      destructive: true,
    );
    if (reason == null) return;
    await _setStatus(member, suspend: true, reason: reason.isEmpty ? null : reason);
  }

  Future<void> _reactivate(AdminMemberRow member) async {
    final confirmed = await _confirm(
      title: 'Reactivate ${member.fullName}?',
      message: 'They will be able to sign in again.',
      confirmLabel: 'Reactivate',
    );
    if (!confirmed) return;
    await _setStatus(member, suspend: false, reason: null);
  }

  Future<void> _setStatus(AdminMemberRow member, {required bool suspend, String? reason}) async {
    setState(() => _busyId = member.id);
    try {
      await _service.setSuspended(member.id, suspend, reason);
      if (!mounted) return;
      setState(() {
        _members = _members
            .map((m) => m.id == member.id
                ? AdminMemberRow(
                    id: m.id,
                    firstName: m.firstName,
                    lastName: m.lastName,
                    email: m.email,
                    role: m.role,
                    accountStatus: suspend ? 'suspended' : 'active',
                    companyName: m.companyName,
                  )
                : m)
            .toList();
        _busyId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(suspend ? '${member.fullName} suspended.' : '${member.fullName} reactivated.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthErrorMapper.fromAny(e))));
    }
  }

  Future<void> _remove(AdminMemberRow member) async {
    final confirmed = await _confirm(
      title: "Remove ${member.fullName}'s account permanently?",
      message:
          'Their profile, posts, comments, connections, messages and applications are deleted. This can\'t be undone.',
      confirmLabel: 'Remove permanently',
      destructive: true,
    );
    if (!confirmed) return;
    final reason = await _promptReason(
      title: 'Reason for removal',
      message: 'Kept in the admin audit log.',
      confirmLabel: 'Confirm removal',
      destructive: true,
    );
    if (reason == null) return;

    setState(() => _busyId = member.id);
    try {
      await _service.removeAccount(member.id, reason.isEmpty ? null : reason);
      if (!mounted) return;
      setState(() {
        _members = _members.where((m) => m.id != member.id).toList();
        _busyId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${member.fullName} removed.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthErrorMapper.fromAny(e))));
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: destructive ? AppColors.error : null),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// Confirm-and-collect-a-reason in one dialog, matching the web console's
  /// prompt-after-confirm flow but as a single sheet instead of two native
  /// dialogs. Returns null on cancel, otherwise the (possibly empty) reason.
  Future<String?> _promptReason({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            SizedBox(height: AppSpace.base),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Reason (kept in the admin log)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            style: TextButton.styleFrom(foregroundColor: destructive ? AppColors.error : null),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result;
  }

  Widget _statusBadge(String status) {
    final colors = {
      'active': AppColors.successGreen,
      'pending': AppColors.secondary,
      'suspended': AppColors.error,
      'rejected': AppColors.onSurfaceVariant,
    };
    final color = colors[status] ?? AppColors.onSurfaceVariant;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        status[0].toUpperCase() + status.substring(1),
        style: AppText.labelBadge(color: color),
      ),
    );
  }

  Widget _pendingBusinessCard(AdminMemberRow business) {
    final busy = _busyId == business.id;
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpace.sm),
      child: RoundedCard(
        child: Row(
          children: [
            InitialsAvatar(
              initials: business.fullName.split(' ').where((s) => s.isNotEmpty).map((e) => e[0]).take(2).join(),
            ),
            SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(business.companyName ?? business.fullName, style: AppText.labelLg()),
                  Text(business.email,
                      style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (busy)
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            else ...[
              IconButton(
                tooltip: 'Approve',
                icon: Icon(Icons.check_circle_outline, color: AppColors.successGreen),
                onPressed: () => _approveBusiness(business),
              ),
              IconButton(
                tooltip: 'Reject',
                icon: Icon(Icons.cancel_outlined, color: AppColors.error),
                onPressed: () => _rejectBusiness(business),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pendingOpportunityCard(AdminOpportunityRow opportunity) {
    final busy = _busyId == opportunity.id;
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpace.sm),
      child: RoundedCard(
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.secondaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(Icons.business_center_outlined, color: AppColors.secondary),
            ),
            SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(opportunity.title, style: AppText.labelLg(), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(opportunity.companyName ?? 'Unknown company',
                      style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (busy)
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            else ...[
              IconButton(
                tooltip: 'Approve',
                icon: Icon(Icons.check_circle_outline, color: AppColors.successGreen),
                onPressed: () => _approveOpportunity(opportunity),
              ),
              IconButton(
                tooltip: 'Reject',
                icon: Icon(Icons.cancel_outlined, color: AppColors.error),
                onPressed: () => _rejectOpportunity(opportunity),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _memberRow(AdminMemberRow member) {
    final busy = _busyId == member.id;
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpace.sm),
      child: RoundedCard(
        padding: EdgeInsets.symmetric(horizontal: AppSpace.base, vertical: AppSpace.sm),
        child: Row(
          children: [
            InitialsAvatar(
              initials: member.fullName.split(' ').where((s) => s.isNotEmpty).map((e) => e[0]).take(2).join(),
              radius: 18,
            ),
            SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.fullName, style: AppText.labelMd(), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    '${member.email} · ${member.role[0].toUpperCase()}${member.role.substring(1)}',
                    style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            SizedBox(width: AppSpace.sm),
            _statusBadge(member.accountStatus),
            if (busy)
              Padding(
                padding: EdgeInsets.only(left: 8),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              PopupMenuButton<String>(
                tooltip: 'Actions',
                icon: Icon(Icons.more_vert, color: AppColors.onSurfaceVariant),
                onSelected: (value) {
                  switch (value) {
                    case 'suspend':
                      _suspend(member);
                      break;
                    case 'reactivate':
                      _reactivate(member);
                      break;
                    case 'remove':
                      _remove(member);
                      break;
                  }
                },
                itemBuilder: (_) => [
                  if (member.accountStatus == 'active')
                    PopupMenuItem(value: 'suspend', child: Text('Suspend')),
                  if (member.accountStatus == 'suspended')
                    PopupMenuItem(value: 'reactivate', child: Text('Reactivate')),
                  PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove account', style: TextStyle(color: AppColors.error)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(AppSpace.base, AppSpace.sm, AppSpace.base, 24),
        children: [
          RichfieldHeader(title: 'Moderation', subtitle: 'RICHFIELD STAFF'),
          if (_error != null) ...[
            Text(_error!, style: AppText.bodySm(color: AppColors.error)),
            TextButton(onPressed: _load, child: Text('Try again')),
          ] else if (_loading)
            Padding(
              padding: EdgeInsets.all(AppSpace.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            SectionHeader(title: 'Pending Businesses'),
            if (_pendingBusinesses.isEmpty)
              Padding(
                padding: EdgeInsets.only(bottom: AppSpace.base),
                child: Text(
                  'No business accounts waiting for approval.',
                  style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                ),
              )
            else
              ..._pendingBusinesses.map(_pendingBusinessCard),
            SizedBox(height: AppSpace.base),
            SectionHeader(title: 'Pending Opportunities'),
            if (_pendingOpportunities.isEmpty)
              Padding(
                padding: EdgeInsets.only(bottom: AppSpace.base),
                child: Text(
                  'No opportunity listings waiting for approval.',
                  style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                ),
              )
            else
              ..._pendingOpportunities.map(_pendingOpportunityCard),
            SizedBox(height: AppSpace.base),
            SectionHeader(title: 'Members'),
            TextField(
              decoration: InputDecoration(
                hintText: 'Search name or email',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
            SizedBox(height: AppSpace.sm),
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _statuses.length,
                separatorBuilder: (_, __) => SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final status = _statuses[i];
                  final selected = _statusFilter == status;
                  return ChoiceChip(
                    label: Text(status == 'all' ? 'All' : status[0].toUpperCase() + status.substring(1)),
                    selected: selected,
                    onSelected: (_) => setState(() => _statusFilter = status),
                    labelStyle:
                        AppText.labelMd(color: selected ? AppColors.onPrimary : AppColors.onSurfaceVariant),
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.surfaceContainerLowest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      side: BorderSide(color: selected ? Colors.transparent : AppColors.outlineVariant),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: AppSpace.md),
            if (_visibleMembers.isEmpty)
              Text('No members match.', style: AppText.bodySm(color: AppColors.onSurfaceVariant))
            else
              ..._visibleMembers.map(_memberRow),
          ],
        ],
      ),
    );
  }
}

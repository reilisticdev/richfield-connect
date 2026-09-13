// mobile/lib/screens/notifications_screen.dart
//
// The bell (rubric 8.1 / guidelines 2.8). Rows are written server-side by the
// triggers in migration 026 — connection requests and acceptances, new
// messages, skill-matched opportunities, published events, activity on your
// posts — plus broadcast_announcement() from the admin panel. New rows arrive
// over RealtimeHub's WebSocket while this screen is open.
//
// openNotificationTarget() is also what the in-app alert's "View" action in
// RootShell calls, so a notification opens the same place from either.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart' show AppColors, AppRadius, AppSpace, AppText, Pill;
import '../services/auth_error_mapper.dart';
import '../services/jobs_service.dart';
import '../services/notifications_service.dart';
import '../services/realtime_hub.dart';
import '../widgets/time_labels.dart';
import 'chat_screen.dart';
import 'member_profile_screen.dart';

IconData notificationIcon(String type) {
  switch (type) {
    case 'new_message':
      return Icons.chat_bubble_outline;
    case 'new_connection':
      return Icons.person_add_alt_1;
    case 'connection_accepted':
      return Icons.handshake_outlined;
    case 'opportunity_match':
      return Icons.work_outline;
    case 'event_published':
      return Icons.event_outlined;
    case 'post_activity':
      return Icons.forum_outlined;
    case 'admin_announcement':
      return Icons.campaign_outlined;
    default:
      return Icons.notifications_none_rounded;
  }
}

Color _notificationColor(String type) {
  switch (type) {
    case 'new_message':
      return AppColors.primary;
    case 'new_connection':
    case 'connection_accepted':
      return AppColors.secondary;
    case 'opportunity_match':
      return AppColors.successGreen;
    case 'event_published':
      return AppColors.tertiary;
    default:
      return AppColors.onSurfaceVariant;
  }
}

/// Opens whatever a notification is about.
Future<void> openNotificationTarget(BuildContext context, AppNotification notification) async {
  final payload = notification.payload;
  String? id(String key) => payload[key] as String?;

  switch (notification.type) {
    case 'new_message':
      final sender = id('sender_id');
      if (sender != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChatScreen(partnerId: sender)),
        );
      }
    case 'new_connection':
    case 'connection_accepted':
    case 'post_activity':
      final actor = id('actor_id');
      if (actor != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MemberProfileScreen(profileId: actor)),
        );
      }
    case 'opportunity_match':
      final opportunity = id('opportunity_id');
      if (opportunity != null) {
        final matched = (payload['matched_skills'] as List?)?.whereType<String>().toList() ?? const [];
        await _showSheet(context, _OpportunitySheet(opportunityId: opportunity, matchedSkills: matched));
      }
    case 'event_published':
      final event = id('event_id');
      if (event != null) await _showSheet(context, _EventSheet(eventId: event));
    default:
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(notificationIcon(notification.type), color: AppColors.primary),
          title: Text(notification.title),
          content: notification.body.isEmpty ? null : Text(notification.body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
          ],
        ),
      );
  }
}

Future<void> _showSheet(BuildContext context, Widget child) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceContainerLowest,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => SafeArea(child: child),
  );
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _client = Supabase.instance.client;
  late final _service = NotificationsService(_client);

  List<AppNotification> _items = [];
  bool _loading = true;
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  String? get _me => _client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
    _subscription = RealtimeHub.instance.notifications.listen((row) {
      if (!mounted) return;
      final incoming = AppNotification.fromRow(row);
      if (_items.any((n) => n.id == incoming.id)) return;
      setState(() => _items = [incoming, ..._items]);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final me = _me;
    if (me == null) return;
    try {
      final items = await _service.fetch(me);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AuthErrorMapper.fromAny(e);
      });
    }
  }

  Future<void> _markAllRead() async {
    final me = _me;
    if (me == null) return;
    setState(() => _items = [for (final n in _items) n.asRead()]);
    try {
      await _service.markAllRead(me);
    } catch (_) {
      // The next load shows the true state; a failed bulk mark isn't worth an error.
    }
    unawaited(RealtimeHub.instance.refreshUnreadNotifications());
  }

  Future<void> _open(AppNotification notification) async {
    if (!notification.isRead) {
      setState(() => _items = [for (final n in _items) n.id == notification.id ? n.asRead() : n]);
      unawaited(_service
          .markRead(notification.id)
          .then((_) => RealtimeHub.instance.refreshUnreadNotifications(), onError: (_) {}));
    }
    await openNotificationTarget(context, notification);
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _items.any((n) => !n.isRead);
    final error = _error;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Notifications', style: AppText.headlineSm()),
        actions: [
          if (hasUnread) TextButton(onPressed: _markAllRead, child: const Text('Mark all read')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.all(AppSpace.base),
                      child: Text(error, style: AppText.bodySm(color: AppColors.error)),
                    )
                  else if (_items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AppSpace.xl),
                      child: Column(
                        children: [
                          Icon(Icons.notifications_none_rounded, size: 40, color: AppColors.onSurfaceVariant),
                          const SizedBox(height: AppSpace.sm),
                          Text('You\'re all caught up', style: AppText.headlineSm()),
                          const SizedBox(height: 4),
                          Text(
                            'Connection requests, messages, matched opportunities and events will show up here.',
                            textAlign: TextAlign.center,
                            style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final n in _items) _tile(n),
                ],
              ),
            ),
    );
  }

  Widget _tile(AppNotification n) {
    final color = _notificationColor(n.type);
    return Material(
      color: n.isRead ? Colors.transparent : AppColors.primary.withOpacity(0.05),
      child: InkWell(
        onTap: () => _open(n),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.base, vertical: AppSpace.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: color.withOpacity(0.15),
                child: Icon(notificationIcon(n.type), size: 20, color: color),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.labelLg().copyWith(
                        fontWeight: n.isRead ? FontWeight.w600 : FontWeight.w800,
                      ),
                    ),
                    if (n.body.isNotEmpty)
                      Text(
                        n.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(relativeAgoLabel(n.createdAt), style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                  if (!n.isRead) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpportunitySheet extends StatefulWidget {
  const _OpportunitySheet({required this.opportunityId, required this.matchedSkills});

  final String opportunityId;
  final List<String> matchedSkills;

  @override
  State<_OpportunitySheet> createState() => _OpportunitySheetState();
}

class _OpportunitySheetState extends State<_OpportunitySheet> {
  final _client = Supabase.instance.client;
  late final Future<Map<String, dynamic>?> _future = _client
      .from('opportunities')
      .select('id, title, description, opportunity_type, required_skills, '
          'profiles(business_profiles(company_name, location))')
      .eq('id', widget.opportunityId)
      .maybeSingle();
  bool _applying = false;

  Future<void> _apply() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;
    setState(() => _applying = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await JobsService(_client).apply(opportunityId: widget.opportunityId, studentId: me);
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Application sent.')));
    } on PostgrestException catch (e) {
      final message = e.code == '23505' ? 'You\'ve already applied to this role.' : AuthErrorMapper.fromAny(e);
      messenger.showSnackBar(SnackBar(content: Text(message)));
      if (mounted) setState(() => _applying = false);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(AuthErrorMapper.fromAny(e))));
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
        }
        final row = snapshot.data;
        if (row == null) {
          return Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Text('This opportunity is no longer available.', style: AppText.bodyMd()),
          );
        }
        final business = (row['profiles'] as Map?)?['business_profiles'] as Map?;
        final company = [business?['company_name'], business?['location']]
            .whereType<String>()
            .where((v) => v.isNotEmpty)
            .join(' • ');
        final matched = widget.matchedSkills.map((s) => s.toLowerCase()).toSet();
        final skills = (row['required_skills'] as List?)?.whereType<String>().toList() ?? const <String>[];

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Pill(
                  text: 'MATCHED TO YOUR PROFILE',
                  icon: Icons.auto_awesome,
                  background: AppColors.successGreenBg,
                  foreground: AppColors.successGreen,
                ),
                const SizedBox(height: AppSpace.sm),
                Text(row['title'] as String? ?? '', style: AppText.headlineMd()),
                if (company.isNotEmpty)
                  Text(company, style: AppText.bodyMd(color: AppColors.onSurfaceVariant)),
                const SizedBox(height: AppSpace.md),
                if (skills.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final skill in skills)
                        matched.contains(skill.toLowerCase())
                            ? Pill(
                                text: skill,
                                icon: Icons.check,
                                background: AppColors.successGreenBg,
                                foreground: AppColors.successGreen,
                              )
                            : Pill(
                                text: skill,
                                background: AppColors.surfaceContainerHigh,
                                foreground: AppColors.onSurfaceVariant,
                              ),
                    ],
                  ),
                const SizedBox(height: AppSpace.md),
                Text(row['description'] as String? ?? '', style: AppText.bodyMd()),
                const SizedBox(height: AppSpace.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _applying ? null : _apply,
                    icon: const Icon(Icons.send_outlined),
                    label: Text(_applying ? 'Applying…' : 'Apply'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EventSheet extends StatelessWidget {
  const _EventSheet({required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: Supabase.instance.client
          .from('events')
          .select('title, description, event_date, location')
          .eq('id', eventId)
          .maybeSingle(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
        }
        final row = snapshot.data;
        if (row == null) {
          return Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Text('This event is no longer available.', style: AppText.bodyMd()),
          );
        }
        final date = DateTime.tryParse(row['event_date'] as String? ?? '')?.toLocal();
        final location = (row['location'] as String?)?.trim() ?? '';
        return Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Pill(
                text: 'RICHFIELD EVENT',
                icon: Icons.event_outlined,
                background: AppColors.tertiaryContainer.withOpacity(0.3),
                foreground: AppColors.tertiary,
              ),
              const SizedBox(height: AppSpace.sm),
              Text(row['title'] as String? ?? '', style: AppText.headlineMd()),
              if (date != null)
                Text(eventDateLabel(date), style: AppText.bodyMd(color: AppColors.onSurfaceVariant)),
              if (location.isNotEmpty)
                Text(location, style: AppText.bodyMd(color: AppColors.onSurfaceVariant)),
              const SizedBox(height: AppSpace.md),
              Text(row['description'] as String? ?? '', style: AppText.bodyMd()),
              const SizedBox(height: AppSpace.md),
            ],
          ),
        );
      },
    );
  }
}

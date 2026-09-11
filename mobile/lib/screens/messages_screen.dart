// mobile/lib/screens/messages_screen.dart
//
// The Messages tab: every accepted connection, most recent conversation
// first (get_my_conversations(), migration 026). Connections nobody has
// written to yet sit in a "Start a conversation" row along the top, so a new
// connection is one tap away from a first message.
//
// Refreshes when RealtimeHub reports an incoming message or a connection
// change — there is no timer.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart'
    show AppColors, AppRadius, AppSpace, AppText, PrimaryButton, RichfieldHeader, RoundedCard, SectionHeader;
import '../services/auth_error_mapper.dart';
import '../services/messaging_service.dart';
import '../services/realtime_hub.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/time_labels.dart';
import 'chat_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key, required this.onFindPeople, required this.onAvatarTap});

  /// Switches the shell to the Network tab from the empty state.
  final VoidCallback onFindPeople;
  final VoidCallback onAvatarTap;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _messaging = MessagingService(Supabase.instance.client);
  final _hub = RealtimeHub.instance;
  final _search = TextEditingController();

  List<Conversation> _all = [];
  bool _loading = true;
  String? _error;
  String _query = '';

  StreamSubscription<Map<String, dynamic>>? _incomingSubscription;
  StreamSubscription<void>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _load();
    _incomingSubscription = _hub.incomingMessages.listen((_) => _load(silent: true));
    _connectionSubscription = _hub.connectionChanges.listen((_) => _load(silent: true));
  }

  @override
  void dispose() {
    _incomingSubscription?.cancel();
    _connectionSubscription?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final conversations = await _messaging.fetchConversations();
      if (!mounted) return;
      setState(() {
        _all = conversations;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      // A failed background refresh keeps the list that's already on screen.
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = AuthErrorMapper.fromAny(e);
      });
    }
  }

  Future<void> _open(Conversation conversation) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(partnerId: conversation.partnerId, partner: conversation.person),
      ),
    );
    if (mounted) _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final matches = q.isEmpty ? _all : _all.where((c) => c.person.name.toLowerCase().contains(q)).toList();
    final threads = matches.where((c) => c.hasMessages).toList();
    final fresh = matches.where((c) => !c.hasMessages).toList();
    final error = _error;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ValueListenableBuilder<int>(
            valueListenable: _hub.unreadMessages,
            builder: (_, unread, __) => RichfieldHeader(
              title: 'Messages',
              subtitle: unread > 0 ? '$unread UNREAD' : 'PRIVATE • CONNECTIONS ONLY',
              onAvatarTap: widget.onAvatarTap,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.base),
            child: TextField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: 'Search conversations',
                filled: true,
                fillColor: AppColors.surfaceContainerLow,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.base),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(AppSpace.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.base),
              child: Column(
                children: [
                  Text(error, style: AppText.bodySm(color: AppColors.error)),
                  TextButton(onPressed: _load, child: const Text('Try again')),
                ],
              ),
            )
          else if (_all.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.base),
              child: _emptyCard(),
            )
          else ...[
            if (fresh.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.base),
                child: SectionHeader(title: 'Start a conversation'),
              ),
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.base),
                  itemCount: fresh.length,
                  separatorBuilder: (_, __) => const SizedBox(width: AppSpace.md),
                  itemBuilder: (_, i) => _freshTile(fresh[i]),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.base),
              child: SectionHeader(title: 'Conversations'),
            ),
            if (threads.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.base),
                child: Text(
                  q.isEmpty
                      ? 'No messages yet — pick a connection above to say hello.'
                      : 'No conversations match "${_query.trim()}".',
                  style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                ),
              )
            else
              ...threads.map(_threadTile),
          ],
        ],
      ),
    );
  }

  Widget _freshTile(Conversation c) {
    return InkWell(
      onTap: () => _open(c),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: SizedBox(
        width: 68,
        child: Column(
          children: [
            ProfileAvatar(
              firstName: c.person.firstName,
              lastName: c.person.lastName,
              avatarPath: c.person.avatarPath,
              radius: 28,
            ),
            const SizedBox(height: 6),
            Text(
              c.person.firstName.isEmpty ? c.person.name : c.person.firstName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppText.labelMd(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _threadTile(Conversation c) {
    final unread = c.unreadCount > 0;
    final preview = '${c.lastFromMe ? 'You: ' : ''}${c.lastMessage ?? ''}'.replaceAll('\n', ' ');
    final sentAt = c.lastSentAt;

    return InkWell(
      onTap: () => _open(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.base, vertical: 10),
        child: Row(
          children: [
            ProfileAvatar(
              firstName: c.person.firstName,
              lastName: c.person.lastName,
              avatarPath: c.person.avatarPath,
              radius: 24,
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.person.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.labelLg().copyWith(
                            fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (sentAt != null)
                        Text(
                          conversationTimeLabel(sentAt),
                          style: AppText.bodySm(
                            color: unread ? AppColors.primary : AppColors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodySm(
                            color: unread ? AppColors.onSurface : AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (unread)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                          child: Text(
                            '${c.unreadCount}',
                            style: AppText.labelBadge(color: AppColors.onPrimary),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard() {
    return RoundedCard(
      child: Column(
        children: [
          Icon(Icons.forum_outlined, size: 40, color: AppColors.primary),
          const SizedBox(height: AppSpace.sm),
          Text('No conversations yet', style: AppText.headlineSm()),
          const SizedBox(height: 4),
          Text(
            'Messages are private and open only between connections. Connect with classmates, '
            'alumni and recruiters to start chatting.',
            textAlign: TextAlign.center,
            style: AppText.bodySm(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpace.md),
          PrimaryButton(
            label: 'Find people',
            icon: Icons.person_add_alt_1,
            onPressed: widget.onFindPeople,
          ),
        ],
      ),
    );
  }
}

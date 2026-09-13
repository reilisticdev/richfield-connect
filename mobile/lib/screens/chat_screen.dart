// mobile/lib/screens/chat_screen.dart
//
// One private conversation (guidelines 2.4: "Direct messaging, connected
// users can send private messages to one another").
//
// Delivery runs over Supabase Realtime's WebSocket (RealtimeHub) — nothing
// polls. Your own message shows immediately and settles when the insert
// returns; its tick becomes a double tick when the other person opens the
// chat, driven by their read_at update arriving on the same socket.
//
// Messaging needs an accepted connection — messages' RLS rejects anything
// else — so without one the composer is replaced by a Connect prompt rather
// than letting someone type a message the database will refuse.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart' show AppColors, AppRadius, AppSpace, AppText;
import '../services/ai_service.dart';
import '../services/auth_error_mapper.dart';
import '../services/connections_service.dart';
import '../services/messaging_service.dart';
import '../services/profile_context_service.dart';
import '../services/realtime_hub.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/time_labels.dart';
import 'member_profile_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.partnerId, this.partner});

  final String partnerId;

  /// Passed when the caller already has the name and photo; fetched when the
  /// chat is opened from a notification that only carries an id.
  final PersonSummary? partner;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _client = Supabase.instance.client;
  late final _messaging = MessagingService(_client);
  late final _connections = ConnectionsService(_client);
  final _hub = RealtimeHub.instance;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  PersonSummary? _partner;
  List<ChatMessage> _messages = [];
  bool _loading = true;
  String? _error;
  bool _connected = true;
  bool _requestSent = false;
  bool _drafting = false;

  StreamSubscription<Map<String, dynamic>>? _incomingSubscription;
  StreamSubscription<Map<String, dynamic>>? _receiptSubscription;

  String? get _me => _client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _partner = widget.partner;
    _hub.activeChatPartnerId = widget.partnerId;
    _incomingSubscription = _hub.incomingMessages.listen(_onIncoming);
    _receiptSubscription = _hub.messageUpdates.listen(_onReadReceipt);
    _load();
  }

  @override
  void dispose() {
    if (_hub.activeChatPartnerId == widget.partnerId) _hub.activeChatPartnerId = null;
    _incomingSubscription?.cancel();
    _receiptSubscription?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final me = _me;
    if (me == null) {
      setState(() {
        _loading = false;
        _error = 'Your session has expired. Sign in again.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object?>([
        _messaging.fetchThread(me: me, partnerId: widget.partnerId),
        _connections.isConnected(me: me, personId: widget.partnerId),
        if (_partner == null)
          _client
              .from('profiles')
              .select(ConnectionsService.personFields)
              .eq('id', widget.partnerId)
              .maybeSingle(),
      ]);
      if (!mounted) return;
      final profileRow = results.length > 2 ? results[2] as Map<String, dynamic>? : null;
      setState(() {
        _messages = results[0] as List<ChatMessage>;
        _connected = results[1] as bool;
        if (profileRow != null) _partner = PersonSummary.fromRow(profileRow);
        _loading = false;
      });
      unawaited(_markRead());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AuthErrorMapper.fromAny(e);
      });
    }
  }

  Future<void> _markRead() async {
    final me = _me;
    if (me == null) return;
    try {
      await _messaging.markThreadRead(me: me, partnerId: widget.partnerId);
      if (mounted) {
        final now = DateTime.now();
        setState(() => _messages = [
              for (final m in _messages)
                m.senderId == widget.partnerId && m.readAt == null ? m.copyWith(readAt: now) : m,
            ]);
      }
    } catch (_) {
      // Read receipts are best-effort; never block the conversation on them.
    }
    unawaited(_hub.refreshUnreadMessages());
    unawaited(_hub.refreshUnreadNotifications());
  }

  void _onIncoming(Map<String, dynamic> row) {
    if (row['sender_id'] != widget.partnerId || !mounted) return;
    final message = ChatMessage.fromRow(row);
    if (_messages.any((m) => m.id == message.id)) return;
    setState(() => _messages = [..._messages, message]);
    _scrollToLatest();
    unawaited(_markRead());
  }

  void _onReadReceipt(Map<String, dynamic> row) {
    if (row['recipient_id'] != widget.partnerId || !mounted) return;
    final updated = ChatMessage.fromRow(row);
    setState(() => _messages = [
          for (final m in _messages) m.id == updated.id ? m.copyWith(readAt: updated.readAt) : m,
        ]);
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send({ChatMessage? retry}) async {
    final me = _me;
    final body = (retry?.body ?? _input.text).trim();
    if (me == null || body.isEmpty) return;
    if (body.length > 4000) {
      _snack('Messages can be up to 4,000 characters.');
      return;
    }

    final local = ChatMessage(
      id: retry?.id ?? 'local-${DateTime.now().microsecondsSinceEpoch}',
      senderId: me,
      recipientId: widget.partnerId,
      body: body,
      sentAt: DateTime.now(),
      pending: true,
    );
    setState(() {
      _messages = retry == null
          ? [..._messages, local]
          : [for (final m in _messages) m.id == retry.id ? local : m];
    });
    if (retry == null) _input.clear();
    _scrollToLatest();

    try {
      final saved = await _messaging.send(me: me, partnerId: widget.partnerId, body: body);
      if (!mounted) return;
      setState(() => _messages = [for (final m in _messages) m.id == local.id ? saved : m]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages = [
            for (final m in _messages)
              m.id == local.id ? local.copyWith(pending: false, failed: true) : m,
          ]);
      _snack(AuthErrorMapper.fromAny(e));
    }
  }

  /// Career AI drafts a first message into the composer; the user edits and
  /// sends it themselves. Only what's already on the other person's profile
  /// card (first name, headline, role) goes to the model — never messages.
  Future<void> _draftOpener() async {
    final me = _me;
    final partner = _partner;
    if (me == null || partner == null || _drafting) return;
    setState(() => _drafting = true);
    try {
      final ctx = await ProfileContextService(_client).load(me);
      final about = [
        if (partner.headline.isNotEmpty) 'their headline is "${partner.headline}"',
        if (partner.roleLabel.isNotEmpty) 'their role on Richfield Connect is ${partner.roleLabel}',
      ].join(' and ');
      final draft = await AiService().chat(
        message: 'Write a short, friendly first message I could send to a new connection named '
            '${partner.firstName.isEmpty ? 'my connection' : partner.firstName}'
            '${about.isEmpty ? '' : ' - $about'}. Mention one relevant thing from my own profile. '
            'Under 45 words. Reply with only the message text: no quotes, no placeholders, no sign-off.',
        profile: ctx.toAssistantJson(),
      );
      if (!mounted) return;
      final text = draft.trim().replaceAll(RegExp(r'^["“]+|["”]+$'), '');
      _input.text = text;
      _input.selection = TextSelection.collapsed(offset: text.length);
    } catch (e) {
      _snack(e is AiServiceException ? e.message : AuthErrorMapper.fromAny(e));
    } finally {
      if (mounted) setState(() => _drafting = false);
    }
  }

  Future<void> _connect() async {
    final me = _me;
    if (me == null) return;
    try {
      await _connections.sendRequest(me: me, personId: widget.partnerId);
      if (mounted) setState(() => _requestSent = true);
      _snack('Connection request sent.');
    } catch (e) {
      _snack(connectionErrorMessage(e));
    }
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MemberProfileScreen(profileId: widget.partnerId)),
    );
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final partner = _partner;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        titleSpacing: 0,
        title: InkWell(
          onTap: _openProfile,
          child: Row(
            children: [
              ProfileAvatar(
                firstName: partner?.firstName,
                lastName: partner?.lastName,
                avatarPath: partner?.avatarPath,
                radius: 18,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partner?.name ?? 'Conversation',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.labelLg(),
                    ),
                    if ((partner?.subtitle ?? '').isNotEmpty)
                      Text(
                        partner!.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'View profile',
            onPressed: _openProfile,
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _body()),
          if (!_loading && _error == null) _connected ? _composer() : _notConnectedBar(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error, textAlign: TextAlign.center, style: AppText.bodyMd(color: AppColors.error)),
              const SizedBox(height: AppSpace.md),
              OutlinedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) return _emptyState();

    final entries = _entriesNewestFirst();
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(AppSpace.base, AppSpace.sm, AppSpace.base, AppSpace.sm),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final entry = entries[i];
        return entry is DateTime ? _dayHeader(entry) : _bubble(entry as ChatMessage);
      },
    );
  }

  /// For a reversed list: newest message first, with each day's header placed
  /// after that day's oldest message so it renders above them on screen.
  List<Object> _entriesNewestFirst() {
    final entries = <Object>[];
    for (var i = _messages.length - 1; i >= 0; i--) {
      final message = _messages[i];
      entries.add(message);
      final older = i > 0 ? _messages[i - 1] : null;
      if (older == null || !isSameDay(older.sentAt, message.sentAt)) {
        entries.add(DateTime(message.sentAt.year, message.sentAt.month, message.sentAt.day));
      }
    }
    return entries;
  }

  Widget _dayHeader(DateTime day) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Text(dayHeaderLabel(day), style: AppText.labelBadge(color: AppColors.onSurfaceVariant)),
        ),
      ),
    );
  }

  Widget _bubble(ChatMessage m) {
    final mine = m.senderId == _me;
    final foreground = mine ? AppColors.onPrimary : AppColors.onSurface;
    const round = Radius.circular(AppRadius.xl);
    const tail = Radius.circular(AppRadius.sm);

    IconData? statusIcon;
    if (mine) {
      statusIcon = m.failed
          ? Icons.error_outline
          : m.pending
              ? Icons.schedule
              : m.readAt != null
                  ? Icons.done_all
                  : Icons.done;
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: m.failed ? () => _send(retry: m) : null,
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: m.body));
          _snack('Message copied');
        },
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: mine ? AppColors.primary : AppColors.surfaceContainerLowest,
            border: mine ? null : Border.all(color: AppColors.outlineVariant),
            borderRadius: BorderRadius.only(
              topLeft: round,
              topRight: round,
              bottomLeft: mine ? round : tail,
              bottomRight: mine ? tail : round,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(m.body, style: AppText.bodyMd(color: foreground)),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    m.failed ? 'Not sent • tap to retry' : clockLabel(m.sentAt),
                    style: AppText.labelBadge(color: foreground.withOpacity(0.75)),
                  ),
                  if (statusIcon != null) ...[
                    const SizedBox(width: 4),
                    Icon(
                      statusIcon,
                      size: 14,
                      color: m.readAt != null && !m.failed
                          ? AppColors.tertiaryFixed
                          : foreground.withOpacity(0.75),
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

  Widget _emptyState() {
    final partner = _partner;
    final first = (partner?.firstName.isNotEmpty ?? false) ? partner!.firstName : 'there';
    final starters = [
      'Hi $first, thanks for connecting!',
      'I\'d love to hear how you got started in your field.',
      'Are you open to a quick chat about opportunities?',
    ];

    return ListView(
      padding: const EdgeInsets.all(AppSpace.xl),
      children: [
        const SizedBox(height: AppSpace.lg),
        Center(
          child: ProfileAvatar(
            firstName: partner?.firstName,
            lastName: partner?.lastName,
            avatarPath: partner?.avatarPath,
            radius: 36,
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Text(partner?.name ?? '', textAlign: TextAlign.center, style: AppText.headlineSm()),
        if ((partner?.subtitle ?? '').isNotEmpty)
          Text(
            partner!.subtitle,
            textAlign: TextAlign.center,
            style: AppText.bodySm(color: AppColors.onSurfaceVariant),
          ),
        const SizedBox(height: AppSpace.lg),
        Text(
          _connected
              ? 'Start the conversation'
              : 'You can message ${first == 'there' ? 'this member' : first} once you\'re connected.',
          textAlign: TextAlign.center,
          style: AppText.bodyMd(color: AppColors.onSurfaceVariant),
        ),
        if (_connected) ...[
          const SizedBox(height: AppSpace.md),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final starter in starters)
                ActionChip(
                  label: Text(starter, style: AppText.bodySm()),
                  backgroundColor: AppColors.surfaceContainerLowest,
                  side: BorderSide(color: AppColors.outlineVariant),
                  onPressed: () {
                    _input.text = starter;
                    _input.selection = TextSelection.collapsed(offset: starter.length);
                  },
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Center(
            child: TextButton.icon(
              onPressed: _drafting ? null : _draftOpener,
              icon: _drafting
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    )
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(_drafting ? 'Drafting…' : 'Draft an opener with Career AI'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xs, AppSpace.sm, AppSpace.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.outlineVariant)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Write a message…',
                  filled: true,
                  fillColor: AppColors.surfaceContainerLow,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _input,
              builder: (_, value, __) => IconButton.filled(
                tooltip: 'Send',
                onPressed: value.text.trim().isEmpty ? null : () => _send(),
                icon: const Icon(Icons.send_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notConnectedBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.md),
        color: AppColors.surfaceContainerLow,
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 18, color: AppColors.onSurfaceVariant),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                'Messages are private between connections.',
                style: AppText.bodySm(color: AppColors.onSurfaceVariant),
              ),
            ),
            FilledButton.tonal(
              onPressed: _requestSent ? null : _connect,
              child: Text(_requestSent ? 'Requested' : 'Connect'),
            ),
          ],
        ),
      ),
    );
  }
}

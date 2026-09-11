// mobile/lib/services/messaging_service.dart
//
// Direct messages between connected users (guidelines 2.4). messages' RLS
// only lets two people read or write a thread while they have an accepted
// connection, and since migration 026 a recipient may change read_at and
// nothing else — so none of that is re-checked here.

import 'package:supabase_flutter/supabase_flutter.dart';

import 'connections_service.dart';

class Conversation {
  Conversation.fromRow(Map<String, dynamic> row)
      : person = PersonSummary.fromRow(row, idKey: 'partner_id'),
        connectionId = row['connection_id'] as String?,
        lastMessage = row['last_message'] as String?,
        lastSentAt = DateTime.tryParse(row['last_sent_at'] as String? ?? '')?.toLocal(),
        lastFromMe = row['last_from_me'] as bool? ?? false,
        unreadCount = (row['unread_count'] as num?)?.toInt() ?? 0;

  final PersonSummary person;
  final String? connectionId;
  final String? lastMessage;
  final DateTime? lastSentAt;
  final bool lastFromMe;
  final int unreadCount;

  String get partnerId => person.id;

  /// False for an accepted connection nobody has written to yet.
  bool get hasMessages => lastSentAt != null;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.body,
    required this.sentAt,
    this.readAt,
    this.pending = false,
    this.failed = false,
  });

  factory ChatMessage.fromRow(Map<String, dynamic> row) => ChatMessage(
        id: row['id'] as String,
        senderId: row['sender_id'] as String,
        recipientId: row['recipient_id'] as String,
        body: row['body'] as String? ?? '',
        sentAt: DateTime.tryParse(row['sent_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        readAt: DateTime.tryParse(row['read_at'] as String? ?? '')?.toLocal(),
      );

  final String id;
  final String senderId;
  final String recipientId;
  final String body;
  final DateTime sentAt;
  final DateTime? readAt;

  /// Local-only states for an optimistic send that hasn't settled yet.
  final bool pending;
  final bool failed;

  ChatMessage copyWith({DateTime? readAt, bool? pending, bool? failed}) => ChatMessage(
        id: id,
        senderId: senderId,
        recipientId: recipientId,
        body: body,
        sentAt: sentAt,
        readAt: readAt ?? this.readAt,
        pending: pending ?? this.pending,
        failed: failed ?? this.failed,
      );
}

class MessagingService {
  MessagingService(this._client);

  final SupabaseClient _client;

  static const _messageFields = 'id, sender_id, recipient_id, body, sent_at, read_at';

  /// One row per accepted connection, most recent conversation first.
  Future<List<Conversation>> fetchConversations() async {
    final rows = await _client.rpc('get_my_conversations');
    return List<Map<String, dynamic>>.from(rows as List).map(Conversation.fromRow).toList();
  }

  /// The latest [limit] messages between the two of you, oldest first.
  Future<List<ChatMessage>> fetchThread({
    required String me,
    required String partnerId,
    int limit = 200,
  }) async {
    final rows = await _client
        .from('messages')
        .select(_messageFields)
        .or('and(sender_id.eq.$me,recipient_id.eq.$partnerId),'
            'and(sender_id.eq.$partnerId,recipient_id.eq.$me)')
        .order('sent_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows as List)
        .map(ChatMessage.fromRow)
        .toList()
        .reversed
        .toList();
  }

  /// Returns the stored row so the optimistic bubble can adopt the real id
  /// and server timestamp.
  Future<ChatMessage> send({
    required String me,
    required String partnerId,
    required String body,
  }) async {
    final row = await _client
        .from('messages')
        .insert({'sender_id': me, 'recipient_id': partnerId, 'body': body})
        .select(_messageFields)
        .single();
    return ChatMessage.fromRow(row);
  }

  /// Marks everything they sent you as read, and clears the matching
  /// "new message" notifications so the bell doesn't still count a
  /// conversation you have just read.
  Future<void> markThreadRead({required String me, required String partnerId}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client
        .from('messages')
        .update({'read_at': now})
        .eq('recipient_id', me)
        .eq('sender_id', partnerId)
        .isFilter('read_at', null);
    await _client
        .from('notifications')
        .update({'read_at': now})
        .eq('recipient_id', me)
        .eq('type', 'new_message')
        .eq('payload->>sender_id', partnerId)
        .isFilter('read_at', null);
  }
}

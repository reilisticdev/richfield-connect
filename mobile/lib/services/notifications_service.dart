// mobile/lib/services/notifications_service.dart
//
// Reads the notifications table. Rows are only ever written server-side —
// by the triggers in migration 026 and by broadcast_announcement() from the
// admin panel — and a client may change read_at and nothing else.

import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.readAt,
  });

  factory AppNotification.fromRow(Map<String, dynamic> row) {
    var payload = row['payload'];
    // Realtime can hand over a jsonb column still encoded as a string.
    if (payload is String) {
      try {
        payload = jsonDecode(payload);
      } catch (_) {
        payload = null;
      }
    }
    return AppNotification(
      id: row['id'] as String,
      type: row['type'] as String? ?? '',
      payload: payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{},
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      readAt: DateTime.tryParse(row['read_at'] as String? ?? '')?.toLocal(),
    );
  }

  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  String get title {
    final fromPayload = payload['title']?.toString().trim() ?? '';
    if (fromPayload.isNotEmpty) return fromPayload;
    switch (type) {
      case 'new_message':
        return 'New message';
      case 'new_connection':
        return 'New connection request';
      case 'connection_accepted':
        return 'Connection accepted';
      case 'opportunity_match':
        return 'An opportunity that fits you';
      case 'event_published':
        return 'New event';
      case 'admin_announcement':
        return 'Announcement';
      case 'post_activity':
        return 'Activity on your post';
      default:
        return 'Notification';
    }
  }

  /// Triggers write 'body'; broadcast_announcement() (migration 023) writes 'message'.
  String get body => (payload['body'] ?? payload['message'])?.toString().trim() ?? '';

  AppNotification asRead() => AppNotification(
        id: id,
        type: type,
        payload: payload,
        createdAt: createdAt,
        readAt: readAt ?? DateTime.now(),
      );
}

class NotificationsService {
  NotificationsService(this._client);

  final SupabaseClient _client;

  Future<List<AppNotification>> fetch(String me, {int limit = 60}) async {
    final rows = await _client
        .from('notifications')
        .select('id, type, payload, read_at, created_at')
        .eq('recipient_id', me)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows as List).map(AppNotification.fromRow).toList();
  }

  Future<void> markRead(String id) async {
    await _client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .isFilter('read_at', null);
  }

  Future<void> markAllRead(String me) async {
    await _client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('recipient_id', me)
        .isFilter('read_at', null);
  }
}

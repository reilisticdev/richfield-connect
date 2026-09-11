// mobile/lib/services/realtime_hub.dart
//
// One Supabase Realtime channel — a single WebSocket subscription — for the
// signed-in user, shared by the whole app:
//
//   messages       INSERT where recipient_id = me  -> open chats, inbox, tab badge
//   messages       UPDATE where sender_id = me     -> read receipts
//   notifications  INSERT where recipient_id = me  -> bell badge, in-app alerts
//   connections    INSERT/UPDATE involving me      -> Network screen
//
// Guidelines 2.8 require real-time delivery "implemented using WebSockets or
// a push notification service. Polling-based solutions are not acceptable."
// Nothing here polls: unread counts are re-queried only when an event
// arrives or the user reads something.
//
// Screens listen to these streams instead of opening their own channels, so
// opening a chat never adds a subscription and closing one can't tear down
// the tab-bar badge. The tables must be in the supabase_realtime publication
// (migration 026), and Realtime applies each table's SELECT policy per
// subscriber, so these filters are a convenience, not the security boundary.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RealtimeHub {
  RealtimeHub._();

  static final RealtimeHub instance = RealtimeHub._();

  SupabaseClient get _client => Supabase.instance.client;

  RealtimeChannel? _channel;
  String? _userId;
  int _holders = 0;

  final _incomingMessages = StreamController<Map<String, dynamic>>.broadcast();
  final _messageUpdates = StreamController<Map<String, dynamic>>.broadcast();
  final _notifications = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionChanges = StreamController<void>.broadcast();

  Stream<Map<String, dynamic>> get incomingMessages => _incomingMessages.stream;
  Stream<Map<String, dynamic>> get messageUpdates => _messageUpdates.stream;
  Stream<Map<String, dynamic>> get notifications => _notifications.stream;
  Stream<void> get connectionChanges => _connectionChanges.stream;

  final ValueNotifier<int> unreadMessages = ValueNotifier<int>(0);
  final ValueNotifier<int> unreadNotifications = ValueNotifier<int>(0);

  /// The person whose chat is on screen, so a message from them doesn't also
  /// pop an in-app alert over the conversation it just appeared in.
  String? activeChatPartnerId;

  /// Reference-counted rather than start/stop: when the app shell is rebuilt,
  /// the new one mounts before the old one disposes, and a plain stop() from
  /// the old one would close the channel the new one is relying on.
  void retain() {
    _holders++;
    unawaited(_start());
  }

  void release() {
    if (_holders > 0) _holders--;
    if (_holders == 0) unawaited(_stop());
  }

  Future<void> _start() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || userId == _userId) return;

    final previous = _channel;
    _channel = null;
    _userId = userId;
    if (previous != null) await _client.removeChannel(previous);
    if (_userId != userId) return; // stopped or restarted while we waited

    PostgresChangeFilter mine(String column) =>
        PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: column, value: userId);

    void connectionChanged(PostgresChangePayload _) => _connectionChanges.add(null);

    _channel = _client
        .channel('richfield-user-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: mine('recipient_id'),
          callback: (payload) {
            _incomingMessages.add(payload.newRecord);
            unawaited(refreshUnreadMessages());
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: mine('sender_id'),
          callback: (payload) => _messageUpdates.add(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: mine('recipient_id'),
          callback: (payload) {
            _notifications.add(payload.newRecord);
            unawaited(refreshUnreadNotifications());
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'connections',
          filter: mine('addressee_id'),
          callback: connectionChanged,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'connections',
          filter: mine('addressee_id'),
          callback: connectionChanged,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'connections',
          filter: mine('requester_id'),
          callback: connectionChanged,
        )
        .subscribe((status, error) {
          debugPrint('Realtime channel: $status${error == null ? '' : ' ($error)'}');
        });

    await Future.wait([refreshUnreadMessages(), refreshUnreadNotifications()]);
  }

  Future<void> _stop() async {
    final previous = _channel;
    _channel = null;
    _userId = null;
    activeChatPartnerId = null;
    unreadMessages.value = 0;
    unreadNotifications.value = 0;
    if (previous != null) await _client.removeChannel(previous);
  }

  Future<void> refreshUnreadMessages() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      unreadMessages.value = await _client
          .from('messages')
          .count(CountOption.exact)
          .eq('recipient_id', userId)
          .isFilter('read_at', null);
    } catch (e) {
      debugPrint('Unread message count failed: $e');
    }
  }

  Future<void> refreshUnreadNotifications() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      unreadNotifications.value = await _client
          .from('notifications')
          .count(CountOption.exact)
          .eq('recipient_id', userId)
          .isFilter('read_at', null);
    } catch (e) {
      debugPrint('Unread notification count failed: $e');
    }
  }
}

// mobile/lib/services/blocks_service.dart
//
// Blocking is independent of connection state (migration 042) - it stops new
// messages and new connection requests in both directions without touching
// message history or an existing accepted connection.

import 'package:supabase_flutter/supabase_flutter.dart';

class BlocksService {
  BlocksService(this._client);

  final SupabaseClient _client;

  Future<void> block(String profileId) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;
    await _client.from('blocks').insert({'blocker_id': me, 'blocked_id': profileId});
  }

  Future<void> unblock(String profileId) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;
    await _client.from('blocks').delete().eq('blocker_id', me).eq('blocked_id', profileId);
  }

  /// True only if the signed-in member has blocked [profileId]. Whether the
  /// other party has blocked *you* is invisible by design - the blocks
  /// table's SELECT policy only ever returns rows you created, so a message
  /// or connection request can still fail even when this returns false.
  Future<bool> hasBlocked(String profileId) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return false;
    final row = await _client
        .from('blocks')
        .select('blocker_id')
        .eq('blocker_id', me)
        .eq('blocked_id', profileId)
        .maybeSingle();
    return row != null;
  }
}

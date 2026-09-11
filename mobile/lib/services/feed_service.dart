// mobile/lib/services/feed_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class FeedService {
  FeedService(this._client);
  final SupabaseClient _client;

  /// Columns every post card needs, with the author's name/role embedded via
  /// posts.author_id -> profiles.id (the only FK from posts to profiles,
  /// so the embed is unambiguous).
  ///
  /// `post_reposts(count)`, `reactions(count)` and `comments(count)` are
  /// PostgREST aggregate embeds: each returns [{'count': n}] per row, so a
  /// card renders real totals without an N+1 query. Each of those tables has
  /// exactly one FK to posts. `!inner` is deliberately NOT used — inner would
  /// drop every post with zero of them.
  static const postFields = 'id, body, image_path, video_path, thumbnail_path, created_at, '
      'profiles(first_name, last_name, role, avatar_path), '
      'post_reposts(count), reactions(count), comments(count)';

  Future<List<Map<String, dynamic>>> fetchRecentPosts({int limit = 30}) async {
    final rows = await _client
        .from('posts')
        .select(postFields)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// One member's own posts, newest first — the Portfolio tab's activity.
  Future<List<Map<String, dynamic>>> fetchPostsByAuthor(String authorId, {int limit = 20}) async {
    final rows = await _client
        .from('posts')
        .select(postFields)
        .eq('author_id', authorId)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Posts a member reposted, newest repost first, as
  /// {created_at: <when reposted>, posts: <post row>}. post_reposts has one
  /// FK to posts, so the embed is unambiguous, and the profiles embed inside
  /// it is the ORIGINAL author — which is who the card should credit.
  ///
  /// Reposting never showed up on anyone's profile because the Portfolio tab
  /// had no activity section at all, only MockData.
  Future<List<Map<String, dynamic>>> fetchRepostsBy(String userId, {int limit = 20}) async {
    final rows = await _client
        .from('post_reposts')
        .select('created_at, posts($postFields)')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// The next published event, for the Feed banner. events' SELECT policy
  /// already hides unpublished rows from non-admins; the status filter is
  /// explicit so an administrator's feed doesn't advertise a draft either.
  Future<Map<String, dynamic>?> fetchNextEvent() async {
    return await _client
        .from('events')
        .select('id, title, description, event_date, location')
        .eq('status', 'published')
        .gte('event_date', DateTime.now().toUtc().toIso8601String())
        .order('event_date')
        .limit(1)
        .maybeSingle();
  }

  /// The set of post ids the signed-in user has reposted, so the feed can
  /// render the Repost button in its correct on/off state on first paint
  /// instead of assuming "not reposted" and flickering after the fact.
  Future<Set<String>> fetchMyRepostedPostIds(String userId) async {
    final rows = await _client
        .from('post_reposts')
        .select('post_id')
        .eq('user_id', userId);
    return List<Map<String, dynamic>>.from(rows as List)
        .map((r) => r['post_id'] as String)
        .toSet();
  }

  /// Creates a post. `imagePath` is a storage object key produced by
  /// MediaService.uploadPostImage — upload first, then persist the path, so
  /// a failed upload never leaves a row pointing at a missing object.
  ///
  /// `.select().single()` is intentional: a bare insert resolves without
  /// error even if RLS rejected the row, which is how a "Posted!" toast can
  /// appear for a post that was never written. Returning the row forces the
  /// failure to surface as a PostgrestException.
  Future<Map<String, dynamic>> createPost({
    required String authorId,
    required String body,
    String? imagePath,
    String? videoPath,
  }) async {
    return await _client
        .from('posts')
        .insert({
          'author_id': authorId,
          'body': body,
          if (imagePath != null) 'image_path': imagePath,
          if (videoPath != null) 'video_path': videoPath,
        })
        .select()
        .single();
  }

  /// Adds a repost. The (post_id, user_id) UNIQUE constraint from migration
  /// 024 makes this idempotent: a double tap raises 23505 rather than
  /// stacking duplicate rows, and we swallow exactly that code.
  Future<void> repost({required String postId, required String userId}) async {
    try {
      await _client.from('post_reposts').insert({
        'post_id': postId,
        'user_id': userId,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') return; // already reposted — desired end state
      rethrow;
    }
  }

  Future<void> undoRepost({required String postId, required String userId}) async {
    await _client
        .from('post_reposts')
        .delete()
        .eq('post_id', postId)
        .eq('user_id', userId);
  }

  /// Toggles and returns the resulting state, so the caller can update its
  /// local count from one round trip.
  Future<bool> toggleRepost({
    required String postId,
    required String userId,
    required bool currentlyReposted,
  }) async {
    if (currentlyReposted) {
      await undoRepost(postId: postId, userId: userId);
      return false;
    }
    await repost(postId: postId, userId: userId);
    return true;
  }
}

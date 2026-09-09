// mobile/lib/services/feed_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class FeedService {
  FeedService(this._client);
  final SupabaseClient _client;

  /// Most recent posts, with the author's name/role embedded via
  /// posts.author_id -> profiles.id (the only FK from posts to profiles,
  /// so the embed is unambiguous).
  Future<List<Map<String, dynamic>>> fetchRecentPosts({int limit = 30}) async {
    final rows = await _client
        .from('posts')
        .select('id, body, video_path, thumbnail_path, created_at, profiles(first_name, last_name, role)')
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<void> createPost({required String authorId, required String body}) {
    return _client.from('posts').insert({
      'author_id': authorId,
      'body': body,
    });
  }
}

// mobile/lib/services/feed_ranker.dart
//
// Ranks the Feed by relevance to the viewer's role and engagement history
// (Guidelines 2.4: "the feed must behave differently for students, alumni
// and business users"). Before this the Feed was the newest 30 posts for
// everyone.
//
// Pure Dart on purpose: the same posts, the same clock, a different role ->
// a different order, and test/feed_ranker_test.dart proves it. Nothing here
// hides a post; ranking only reorders what the member could already see,
// and the "Newest first" chip on the Feed turns it off.
//
// Score, per post (higher = earlier):
//   role affinity   what this viewer is here for: students want hiring
//                   updates and alumni career stories; alumni want students
//                   to mentor and fellow graduates; businesses want talent.
//   connections     posts from people the viewer is connected to.
//   engagement      log-scaled reactions/comments/reposts on the post.
//   history         authors whose posts the viewer already liked or
//                   reposted; the viewer's own already-liked posts drop a
//                   little (seen).
//   format          career reels (video) matter more to students/alumni
//                   and are the business viewer's talent showcase.
//   recency         a steady penalty per hour, capped, so the feed still
//                   reads as a timeline with boosts rather than a lottery.

import 'dart:math';

class RankableFeedPost {
  const RankableFeedPost({
    required this.id,
    required this.authorId,
    required this.authorRole,
    required this.createdAt,
    required this.isVideo,
    required this.hasImage,
    required this.reactions,
    required this.comments,
    required this.reposts,
    required this.viewerReacted,
    required this.viewerReposted,
  });

  final String id;
  final String? authorId;

  /// Lower-case profiles.role: student | alumni | business | administrator.
  final String authorRole;
  final DateTime createdAt;
  final bool isVideo;
  final bool hasImage;
  final int reactions;
  final int comments;
  final int reposts;
  final bool viewerReacted;
  final bool viewerReposted;
}

class FeedRanker {
  FeedRanker._();

  /// Role → author-role → affinity points.
  static const Map<String, Map<String, double>> _affinity = {
    'student': {'business': 3.0, 'alumni': 2.0, 'administrator': 2.0, 'student': 1.0},
    'alumni': {'student': 2.0, 'alumni': 2.0, 'administrator': 1.5, 'business': 1.5},
    'business': {'student': 3.0, 'alumni': 2.5, 'administrator': 1.0, 'business': 0.0},
    'administrator': {'student': 1.0, 'alumni': 1.0, 'business': 1.0, 'administrator': 1.0},
  };

  static const double _connectionBoost = 2.0;
  static const double _historyAuthorBoost = 0.75;
  static const double _seenPenalty = 0.5;
  static const double _recencyPerHour = 1 / 12;
  static const double _recencyCap = 4.0;

  static double _videoBoost(String viewerRole) => switch (viewerRole) {
        'business' => 1.5,
        'student' || 'alumni' => 1.0,
        _ => 0.5,
      };

  /// One human sentence for the Feed header so the ranking is explained,
  /// not mysterious.
  static String explain(String viewerRole) => switch (viewerRole) {
        'student' => 'Ranked for you: hiring updates and alumni career stories first.',
        'alumni' => 'Ranked for you: students you can mentor and fellow graduates first.',
        'business' => 'Ranked for you: student and alumni talent first.',
        'administrator' => 'Newest first.',
        _ => 'Ranked for you.',
      };

  static double score(
    RankableFeedPost post, {
    required String viewerRole,
    required Set<String> connectionIds,
    required Set<String> engagedAuthorIds,
    required DateTime now,
  }) {
    final role = viewerRole.toLowerCase();
    if (role == 'administrator') {
      // Administrators moderate; chronological is the honest order.
      return -now.difference(post.createdAt).inMinutes.toDouble();
    }
    final table = _affinity[role] ?? const <String, double>{};
    var s = table[post.authorRole.toLowerCase()] ?? 1.0;

    final authorId = post.authorId;
    if (authorId != null && connectionIds.contains(authorId)) s += _connectionBoost;
    if (authorId != null && engagedAuthorIds.contains(authorId)) s += _historyAuthorBoost;
    if (post.viewerReacted || post.viewerReposted) s -= _seenPenalty;

    if (post.isVideo) s += _videoBoost(role);
    if (post.hasImage) s += 0.3;

    s += 0.6 * log(1 + post.reactions + 2 * post.comments + post.reposts);

    final hours = now.difference(post.createdAt).inMinutes / 60.0;
    s -= min(_recencyCap, max(0.0, hours) * _recencyPerHour);
    return s;
  }

  /// Returns the posts' ids in ranked order. Stable for equal scores
  /// (newest first among ties).
  static List<String> rankIds(
    List<RankableFeedPost> posts, {
    required String viewerRole,
    required Set<String> connectionIds,
    required Set<String> engagedAuthorIds,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final scored = [
      for (final p in posts)
        (
          id: p.id,
          score: score(p,
              viewerRole: viewerRole,
              connectionIds: connectionIds,
              engagedAuthorIds: engagedAuthorIds,
              now: clock),
          createdAt: p.createdAt,
        ),
    ];
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.createdAt.compareTo(a.createdAt);
    });
    return [for (final s in scored) s.id];
  }
}

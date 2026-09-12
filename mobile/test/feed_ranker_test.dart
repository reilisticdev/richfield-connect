// Guidelines 2.4: the feed must behave differently for students, alumni and
// business users. Same posts, same clock, different viewer -> different
// order. These tests are what "differs by role" means in this codebase.

import 'package:flutter_test/flutter_test.dart';
import 'package:richfield_connect/services/feed_ranker.dart';

RankableFeedPost post(
  String id, {
  required String authorRole,
  String? authorId,
  int minutesAgo = 60,
  bool video = false,
  int reactions = 0,
  int comments = 0,
  bool viewerReacted = false,
}) {
  return RankableFeedPost(
    id: id,
    authorId: authorId ?? 'author-$id',
    authorRole: authorRole,
    createdAt: DateTime(2026, 9, 12, 12).subtract(Duration(minutes: minutesAgo)),
    isVideo: video,
    hasImage: false,
    reactions: reactions,
    comments: comments,
    reposts: 0,
    viewerReacted: viewerReacted,
    viewerReposted: false,
  );
}

final now = DateTime(2026, 9, 12, 12);

List<String> rank(List<RankableFeedPost> posts, String role,
        {Set<String> connections = const {}, Set<String> engaged = const {}}) =>
    FeedRanker.rankIds(posts,
        viewerRole: role, connectionIds: connections, engagedAuthorIds: engaged, now: now);

void main() {
  final posts = [
    post('student-post', authorRole: 'student'),
    post('alumni-story', authorRole: 'alumni'),
    post('business-hiring', authorRole: 'business'),
  ];

  test('a student sees business hiring updates, then alumni stories, then peers', () {
    expect(rank(posts, 'student'), ['business-hiring', 'alumni-story', 'student-post']);
  });

  test('a business sees student talent first and other businesses last', () {
    expect(rank(posts, 'business'), ['student-post', 'alumni-story', 'business-hiring']);
  });

  test('alumni see students and fellow graduates ahead of businesses', () {
    final order = rank(posts, 'alumni');
    expect(order.last, 'business-hiring');
    expect(order.take(2).toSet(), {'student-post', 'alumni-story'});
  });

  test('administrators get plain chronological order', () {
    final mixed = [
      post('old-business', authorRole: 'business', minutesAgo: 300),
      post('new-student', authorRole: 'student', minutesAgo: 5),
    ];
    expect(rank(mixed, 'administrator'), ['new-student', 'old-business']);
  });

  test('a connection outranks a stranger of the same role', () {
    final two = [
      post('stranger', authorRole: 'student', authorId: 'u-stranger'),
      post('friend', authorRole: 'student', authorId: 'u-friend'),
    ];
    expect(rank(two, 'student', connections: {'u-friend'}).first, 'friend');
  });

  test('career reels float for students and are a talent showcase for businesses', () {
    final two = [
      post('text', authorRole: 'alumni'),
      post('reel', authorRole: 'alumni', video: true),
    ];
    expect(rank(two, 'student').first, 'reel');
    expect(rank(two, 'business').first, 'reel');
  });

  test('engagement lifts a post and an already-liked post settles a little', () {
    final two = [
      post('quiet', authorRole: 'student'),
      post('popular', authorRole: 'student', reactions: 12, comments: 4),
    ];
    expect(rank(two, 'student').first, 'popular');
    final liked = [
      post('unseen', authorRole: 'student'),
      post('liked', authorRole: 'student', viewerReacted: true),
    ];
    expect(rank(liked, 'student').first, 'unseen');
  });

  test('recency still matters: a two-day-old hiring post does not bury today\'s', () {
    final two = [
      post('today-student', authorRole: 'student', minutesAgo: 30),
      post('stale-business', authorRole: 'business', minutesAgo: 60 * 72),
    ];
    // affinity 3 - capped recency 4 < affinity 1 - ~0.04
    expect(rank(two, 'student').first, 'today-student');
  });
}

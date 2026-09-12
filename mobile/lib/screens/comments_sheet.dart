// mobile/lib/screens/comments_sheet.dart
//
// Comments on a feed post: read them, add one, delete your own, report
// someone else's. Any signed-in member can read comments; RLS only lets you
// write as yourself, and migration 032 rejects blank or 1000+ character
// comments. The post's author is notified by notify_post_activity().

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart' show AppColors, AppRadius, AppSpace, AppText;
import '../services/auth_error_mapper.dart';
import '../services/feed_service.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/report_content_dialog.dart';
import '../widgets/time_labels.dart';

const _maxLength = 1000;

/// [onCountChanged] receives the new total after each add or delete, so the
/// card can update its count without reloading the feed.
Future<void> showCommentsSheet(
  BuildContext context, {
  required String postId,
  required ValueChanged<int> onCountChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surfaceContainerLowest,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => _CommentsSheet(postId: postId, onCountChanged: onCountChanged),
  );
}

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.postId, required this.onCountChanged});

  final String postId;
  final ValueChanged<int> onCountChanged;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _client = Supabase.instance.client;
  late final _feed = FeedService(_client);
  final _input = TextEditingController();

  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  String? get _me => _client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await _feed.fetchComments(widget.postId);
      if (!mounted) return;
      setState(() {
        _comments = rows;
        _loading = false;
        _error = null;
      });
      widget.onCountChanged(rows.length);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AuthErrorMapper.fromAny(e);
      });
    }
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    final me = _me;
    if (body.isEmpty || _sending || me == null) return;

    setState(() => _sending = true);
    try {
      final row = await _feed.addComment(postId: widget.postId, authorId: me, body: body);
      if (!mounted) return;
      _input.clear();
      setState(() {
        _comments = [..._comments, row];
        _sending = false;
      });
      widget.onCountChanged(_comments.length);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthErrorMapper.fromAny(e))));
    }
  }

  Future<void> _delete(Map<String, dynamic> comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete your comment?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _feed.deleteComment(comment['id'] as String);
      if (!mounted) return;
      setState(() => _comments = _comments.where((c) => c['id'] != comment['id']).toList());
      widget.onCountChanged(_comments.length);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthErrorMapper.fromAny(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            const SizedBox(height: AppSpace.sm),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.base, AppSpace.sm, AppSpace.xs, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _loading ? 'Comments' : 'Comments (${_comments.length})',
                      style: AppText.headlineSm(),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.outlineVariant.withValues(alpha: 0.5)),
            Expanded(child: _body()),
            Divider(height: 1, color: AppColors.outlineVariant.withValues(alpha: 0.5)),
            _composer(),
          ],
        ),
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
              OutlinedButton(
                onPressed: () {
                  setState(() => _loading = true);
                  _load();
                },
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_comments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Text(
            'No comments yet. Start the conversation.',
            textAlign: TextAlign.center,
            style: AppText.bodyMd(color: AppColors.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      itemCount: _comments.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpace.xs),
      itemBuilder: (_, i) => _tile(_comments[i]),
    );
  }

  Widget _tile(Map<String, dynamic> comment) {
    final author = comment['profiles'] as Map<String, dynamic>?;
    final first = author?['first_name'] as String?;
    final last = author?['last_name'] as String?;
    final name = '${first ?? ''} ${last ?? ''}'.trim();
    final created = DateTime.tryParse(comment['created_at'] as String? ?? '');
    final mine = comment['author_id'] == _me;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.base, AppSpace.xs, AppSpace.xs, AppSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileAvatar(firstName: first, lastName: last, avatarPath: author?['avatar_path'] as String?, radius: 16),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name.isEmpty ? 'Richfield member' : name,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.labelMd(),
                      ),
                    ),
                    if (created != null) ...[
                      const SizedBox(width: AppSpace.sm),
                      Text(relativeAgoLabel(created.toLocal()), style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment['body'] as String? ?? '', style: AppText.bodyMd()),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: Icon(Icons.more_vert, size: 18, color: AppColors.onSurfaceVariant),
            onSelected: (value) {
              if (value == 'delete') {
                _delete(comment);
              } else {
                showReportContentDialog(context, contentType: 'comment', contentId: comment['id'] as String);
              }
            },
            itemBuilder: (_) => [
              if (mine)
                const PopupMenuItem(value: 'delete', child: Text('Delete'))
              else
                const PopupMenuItem(value: 'report', child: Text('Report comment')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.base, AppSpace.sm, AppSpace.sm, AppSpace.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                enabled: !_sending,
                minLines: 1,
                maxLines: 4,
                maxLength: _maxLength,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Add a comment',
                  counterText: '',
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            IconButton(
              tooltip: 'Post comment',
              onPressed: _sending || _input.text.trim().isEmpty ? null : _send,
              icon: _sending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.send_rounded, color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

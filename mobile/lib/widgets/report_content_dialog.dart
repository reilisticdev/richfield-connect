// mobile/lib/widgets/report_content_dialog.dart
//
// Report a post or comment. Reports land in content_reports, which the web
// Moderation page reviews; migration 032 lets administrators remove the
// content from there.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_error_mapper.dart';
import '../services/feed_service.dart';

const _reasons = [
  'Spam or misleading',
  'Harassment or hate',
  'Inappropriate or offensive',
  'False information about a person or company',
  'Something else',
];

/// [contentType] is one of content_reports' allowed types: post, video or comment.
Future<void> showReportContentDialog(
  BuildContext context, {
  required String contentType,
  required String contentId,
}) async {
  final noun = contentType == 'comment' ? 'comment' : 'post';
  final reason = await showDialog<String>(
    context: context,
    builder: (_) => _ReportDialog(noun: noun),
  );
  if (reason == null || !context.mounted) return;

  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await FeedService(client).reportContent(
      contentType: contentType,
      contentId: contentId,
      reporterId: userId,
      reason: reason,
    );
    messenger.showSnackBar(
      SnackBar(content: Text('Thanks. A Richfield administrator will review this $noun.')),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(AuthErrorMapper.fromAny(e))));
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.noun});

  final String noun;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _details = TextEditingController();
  String? _picked;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  bool get _needsDetails => _picked == _reasons.last;

  bool get _ready => _picked != null && (!_needsDetails || _details.text.trim().isNotEmpty);

  String get _reason {
    final details = _details.text.trim();
    return details.isEmpty ? _picked! : '${_picked!}: $details';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Report this ${widget.noun}'),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final reason in _reasons)
              ListTile(
                dense: true,
                leading: Icon(_picked == reason ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                title: Text(reason),
                onTap: () => setState(() => _picked = reason),
              ),
            if (_needsDetails)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _details,
                  autofocus: true,
                  maxLength: 300,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(hintText: 'What is wrong with it?'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _ready ? () => Navigator.pop(context, _reason) : null,
          child: const Text('Report'),
        ),
      ],
    );
  }
}

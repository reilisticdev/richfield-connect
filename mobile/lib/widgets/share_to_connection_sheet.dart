// mobile/lib/widgets/share_to_connection_sheet.dart
//
// "Share to a connection" (Keshav's request): the post is sent as a plain
// message to whichever accepted connections the member picks, through the
// existing messages table/RLS - not a new sharing mechanism, just the
// ordinary DM path. messages RLS already only lets the two people on a
// thread read it, so "only that connection can see it" is enforced the same
// way a normal chat message is, with no new policy needed.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart' show AppColors, AppRadius, AppSpace, AppText, FeedPost, postShareText;
import '../services/auth_error_mapper.dart';
import '../services/connections_service.dart';
import '../services/messaging_service.dart';
import 'profile_avatar.dart';

Future<void> showShareToConnectionSheet(BuildContext context, FeedPost post) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceContainerLowest,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => SafeArea(child: _ShareToConnectionSheet(post: post)),
  );
}

class _ShareToConnectionSheet extends StatefulWidget {
  const _ShareToConnectionSheet({required this.post});

  final FeedPost post;

  @override
  State<_ShareToConnectionSheet> createState() => _ShareToConnectionSheetState();
}

class _ShareToConnectionSheetState extends State<_ShareToConnectionSheet> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<PersonSummary> _connections = [];
  final Set<String> _selected = {};
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;
    try {
      final snapshot = await ConnectionsService(_client).load(me);
      if (!mounted) return;
      setState(() {
        _connections = snapshot.connected.map((e) => e.person).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AuthErrorMapper.fromAny(e);
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final me = _client.auth.currentUser?.id;
    if (me == null || _selected.isEmpty) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final text = postShareText(widget.post);
    final messaging = MessagingService(_client);

    var failures = 0;
    for (final partnerId in _selected) {
      try {
        await messaging.send(me: me, partnerId: partnerId, body: text);
      } catch (_) {
        failures++;
      }
    }

    if (!mounted) return;
    navigator.pop();
    final sent = _selected.length - failures;
    final noun = sent == 1 ? 'connection' : 'connections';
    messenger.showSnackBar(SnackBar(
      content: Text(
        failures == 0
            ? 'Shared with $sent $noun.'
            : sent == 0
                ? "Couldn't share — try again."
                : 'Shared with $sent $noun — $failures failed.',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(AppSpace.base, AppSpace.base, AppSpace.base, AppSpace.xs),
            child: Text('Share to a connection', style: AppText.headlineSm()),
          ),
          Flexible(
            child: _loading
                ? Padding(
                    padding: EdgeInsets.all(AppSpace.xl),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _error != null
                    ? Padding(
                        padding: EdgeInsets.all(AppSpace.base),
                        child: Text(_error!, style: AppText.bodySm(color: AppColors.error)),
                      )
                    : _connections.isEmpty
                        ? Padding(
                            padding: EdgeInsets.all(AppSpace.xl),
                            child: Text(
                              "You don't have any connections yet.",
                              style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                            ),
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final person in _connections)
                                CheckboxListTile(
                                  value: _selected.contains(person.id),
                                  onChanged: (checked) => setState(() {
                                    if (checked ?? false) {
                                      _selected.add(person.id);
                                    } else {
                                      _selected.remove(person.id);
                                    }
                                  }),
                                  secondary: ProfileAvatar(
                                    firstName: person.firstName,
                                    lastName: person.lastName,
                                    avatarPath: person.avatarPath,
                                    radius: 18,
                                  ),
                                  title: Text(person.name),
                                  subtitle: Text(person.subtitle),
                                ),
                            ],
                          ),
          ),
          Padding(
            padding: EdgeInsets.all(AppSpace.base),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selected.isEmpty || _sending ? null : _send,
                child: Text(_sending ? 'Sending…' : 'Send'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

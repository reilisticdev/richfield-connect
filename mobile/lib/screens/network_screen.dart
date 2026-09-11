// mobile/lib/screens/network_screen.dart
//
// The Network tab, rebuilt on real data. The previous version was a
// StatelessWidget over MockData.suggestions: three invented people with
// Connect buttons wired to `onPressed: () {}`, a hardcoded pending request
// from "Zanele Mokoena" whose accept/decline did nothing, and
// "482 CONNECTIONS" in the header.
//
// Now (guidelines 2.4 — "send, accept, decline, and manage connection
// requests"):
//   * Invitations — real incoming requests, accept or decline
//   * People you may know — get_connection_suggestions(), ranked by
//     programme and shared skills
//   * Your connections — message or remove
//   * Sent requests — withdraw
//   * Search across active members
// and it refreshes itself when RealtimeHub sees a connection change.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart'
    show AppColors, AppRadius, AppSpace, AppText, RichfieldHeader, RoundedCard, SectionHeader;
import '../services/auth_error_mapper.dart';
import '../services/connections_service.dart';
import '../services/realtime_hub.dart';
import '../widgets/profile_avatar.dart';
import 'chat_screen.dart';
import 'member_profile_screen.dart';

class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key, required this.onAvatarTap});

  final VoidCallback onAvatarTap;

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  final _client = Supabase.instance.client;
  late final _service = ConnectionsService(_client);
  final _search = TextEditingController();
  Timer? _debounce;
  StreamSubscription<void>? _connectionSubscription;

  NetworkSnapshot _snapshot = NetworkSnapshot(const []);
  List<SuggestedPerson> _suggestions = [];

  /// Null while not searching.
  List<PersonSummary>? _results;
  bool _searching = false;
  bool _loading = true;
  String? _error;

  /// Person ids with a request/accept/remove in flight.
  final Set<String> _busy = {};

  String? get _me => _client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
    _connectionSubscription =
        RealtimeHub.instance.connectionChanges.listen((_) => _load(silent: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _connectionSubscription?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final me = _me;
    if (me == null) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait<Object>([_service.load(me), _service.suggestions()]);
      if (!mounted) return;
      setState(() {
        _snapshot = results[0] as NetworkSnapshot;
        _suggestions = results[1] as List<SuggestedPerson>;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = AuthErrorMapper.fromAny(e);
      });
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _results = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    // Runs once the user pauses typing rather than on every keystroke.
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(value));
  }

  Future<void> _runSearch(String value) async {
    final me = _me;
    if (me == null) return;
    try {
      final found = await _service.search(me: me, query: value);
      if (!mounted || _search.text != value) return;
      setState(() {
        _results = found;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _searching = false;
      });
      _snack(AuthErrorMapper.fromAny(e));
    }
  }

  void _clearSearch() {
    _debounce?.cancel();
    _search.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _results = null;
      _searching = false;
    });
  }

  Future<void> _run(String personId, Future<void> Function() action, {String? success}) async {
    if (_busy.contains(personId)) return;
    setState(() => _busy.add(personId));
    try {
      await action();
      await _load(silent: true);
      if (success != null) _snack(success);
    } catch (e) {
      _snack(connectionErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy.remove(personId));
    }
  }

  void _connect(PersonSummary person) {
    final me = _me;
    if (me == null) return;
    _run(
      person.id,
      () => _service.sendRequest(me: me, personId: person.id),
      success: 'Request sent to ${person.firstName.isEmpty ? person.name : person.firstName}.',
    );
  }

  void _respond(ConnectionEdge edge, {required bool accept}) {
    _run(
      edge.person.id,
      () => _service.respond(connectionId: edge.id, accept: accept),
      success: accept ? 'You\'re now connected with ${edge.person.name}.' : 'Request declined.',
    );
  }

  Future<void> _remove(ConnectionEdge edge) async {
    final isRequest = edge.status != 'accepted';
    if (!isRequest) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Remove connection?'),
          content: Text(
            'You and ${edge.person.name} will no longer be able to message each other.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await _run(
      edge.person.id,
      () => _service.remove(edge.id),
      success: isRequest ? 'Request withdrawn.' : 'Connection removed.',
    );
  }

  Future<void> _openChat(PersonSummary person) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(partnerId: person.id, partner: person)),
    );
  }

  Future<void> _openProfile(PersonSummary person) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MemberProfileScreen(profileId: person.id)),
    );
    if (mounted) _load(silent: true);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final connected = _snapshot.connected;
    final incoming = _snapshot.incoming;
    final outgoing = _snapshot.outgoing;
    final searchActive = _results != null || _searching;
    final error = _error;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          RichfieldHeader(
            title: 'Network',
            subtitle: _loading
                ? 'LOADING…'
                : '${connected.length} CONNECTION${connected.length == 1 ? '' : 'S'}',
            onAvatarTap: widget.onAvatarTap,
          ),
          _pad(
            TextField(
              controller: _search,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: searchActive
                    ? IconButton(
                        tooltip: 'Clear search',
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.close, size: 18),
                      )
                    : null,
                hintText: 'Search students, alumni, recruiters…',
                filled: true,
                fillColor: AppColors.surfaceContainerLow,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.base),
          if (searchActive)
            ..._searchResults()
          else if (_loading)
            const Padding(
              padding: EdgeInsets.all(AppSpace.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (error != null)
            _pad(Column(
              children: [
                Text(error, style: AppText.bodySm(color: AppColors.error)),
                TextButton(onPressed: _load, child: const Text('Try again')),
              ],
            ))
          else ...[
            if (incoming.isNotEmpty) ...[
              _pad(SectionHeader(title: 'Invitations', trailing: '${incoming.length}')),
              ...incoming.map(_invitationCard),
              const SizedBox(height: AppSpace.sm),
            ],
            _pad(SectionHeader(title: 'People you may know')),
            if (_suggestions.isEmpty)
              _pad(_muted('No new suggestions right now. Adding skills and education to your '
                  'profile helps us find people like you.'))
            else
              SizedBox(
                height: 224,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.base),
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: AppSpace.sm),
                  itemBuilder: (_, i) => _suggestionCard(_suggestions[i]),
                ),
              ),
            const SizedBox(height: AppSpace.lg),
            _pad(SectionHeader(
              title: 'Your connections',
              trailing: connected.isEmpty ? null : '${connected.length}',
            )),
            if (connected.isEmpty)
              _pad(_muted('Connect with people to message them and follow their updates.'))
            else
              ...connected.map(_connectionTile),
            if (outgoing.isNotEmpty) ...[
              const SizedBox(height: AppSpace.lg),
              _pad(SectionHeader(title: 'Sent requests')),
              ...outgoing.map(_sentTile),
            ],
          ],
        ],
      ),
    );
  }

  Widget _pad(Widget child) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.base), child: child);

  Widget _muted(String text) => Text(text, style: AppText.bodySm(color: AppColors.onSurfaceVariant));

  Widget _spinner() => const SizedBox(
        width: 28,
        height: 28,
        child: Padding(padding: EdgeInsets.all(4), child: CircularProgressIndicator(strokeWidth: 2)),
      );

  Widget _avatar(PersonSummary p, double radius) => ProfileAvatar(
        firstName: p.firstName,
        lastName: p.lastName,
        avatarPath: p.avatarPath,
        radius: radius,
      );

  Widget _invitationCard(ConnectionEdge edge) {
    final person = edge.person;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.base, 0, AppSpace.base, AppSpace.sm),
      child: RoundedCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(
          children: [
            GestureDetector(onTap: () => _openProfile(person), child: _avatar(person, 24)),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: GestureDetector(
                onTap: () => _openProfile(person),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(person.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.labelLg()),
                    Text(
                      person.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            if (_busy.contains(person.id))
              _spinner()
            else ...[
              IconButton(
                tooltip: 'Decline',
                onPressed: () => _respond(edge, accept: false),
                icon: Icon(Icons.close, color: AppColors.onSurfaceVariant),
              ),
              IconButton.filled(
                tooltip: 'Accept',
                onPressed: () => _respond(edge, accept: true),
                icon: const Icon(Icons.check),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _suggestionCard(SuggestedPerson suggestion) {
    final person = suggestion.person;
    final pending = _snapshot.statusWith(person.id) == RelationStatus.pendingOutgoing;
    return SizedBox(
      width: 164,
      child: RoundedCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          children: [
            GestureDetector(onTap: () => _openProfile(person), child: _avatar(person, 30)),
            const SizedBox(height: AppSpace.sm),
            Text(
              person.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.labelMd(),
            ),
            if (person.roleLabel.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(person.roleLabel.toUpperCase(), style: AppText.labelBadge(color: AppColors.secondary)),
            ],
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                suggestion.reason,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodySm(color: AppColors.onSurfaceVariant),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: _busy.contains(person.id)
                  ? Center(child: _spinner())
                  : pending
                      ? const OutlinedButton(onPressed: null, child: Text('Pending'))
                      : FilledButton.tonal(
                          onPressed: () => _connect(person),
                          child: const Text('Connect'),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _connectionTile(ConnectionEdge edge) {
    final person = edge.person;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.base),
      leading: _avatar(person, 22),
      title: Text(person.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.labelLg()),
      subtitle: Text(
        person.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.bodySm(color: AppColors.onSurfaceVariant),
      ),
      onTap: () => _openProfile(person),
      trailing: _busy.contains(person.id)
          ? _spinner()
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Message',
                  onPressed: () => _openChat(person),
                  icon: Icon(Icons.chat_bubble_outline, color: AppColors.primary),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (value) {
                    if (value == 'remove') _remove(edge);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'remove', child: Text('Remove connection')),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _sentTile(ConnectionEdge edge) {
    final person = edge.person;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.base),
      leading: _avatar(person, 22),
      title: Text(person.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.labelLg()),
      subtitle: Text('Request sent', style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
      onTap: () => _openProfile(person),
      trailing: _busy.contains(person.id)
          ? _spinner()
          : TextButton(onPressed: () => _remove(edge), child: const Text('Withdraw')),
    );
  }

  List<Widget> _searchResults() {
    final results = _results;
    return [
      _pad(SectionHeader(title: 'Search results')),
      if (results == null)
        const Padding(
          padding: EdgeInsets.all(AppSpace.xl),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (results.isEmpty && !_searching)
        _pad(_muted('No one matches "${_search.text.trim()}".'))
      else
        ...results.map((person) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.base),
              leading: _avatar(person, 22),
              title: Text(person.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.labelLg()),
              subtitle: Text(
                person.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodySm(color: AppColors.onSurfaceVariant),
              ),
              onTap: () => _openProfile(person),
              trailing: _actionFor(person),
            )),
    ];
  }

  Widget _actionFor(PersonSummary person) {
    if (_busy.contains(person.id)) return _spinner();
    switch (_snapshot.statusWith(person.id)) {
      case RelationStatus.connected:
        return IconButton(
          tooltip: 'Message',
          onPressed: () => _openChat(person),
          icon: Icon(Icons.chat_bubble_outline, color: AppColors.primary),
        );
      case RelationStatus.pendingOutgoing:
        return Text('Pending', style: AppText.labelMd(color: AppColors.onSurfaceVariant));
      case RelationStatus.pendingIncoming:
        final edge = _snapshot.edgeWith(person.id)!;
        return FilledButton(
          onPressed: () => _respond(edge, accept: true),
          child: const Text('Accept'),
        );
      case RelationStatus.none:
        return FilledButton.tonal(onPressed: () => _connect(person), child: const Text('Connect'));
    }
  }
}

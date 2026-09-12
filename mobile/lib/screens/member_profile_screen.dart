// mobile/lib/screens/member_profile_screen.dart
//
// Another member's profile, as they've allowed you to see it. Skills,
// education, experience, projects and certifications are all read through
// RLS policies that honour the owner's profile_visibility settings, so a
// business user simply gets fewer rows back for a student who has hidden a
// section from businesses (guidelines 2.1 / 2.3) — nothing is filtered here.
//
// Also where the social actions on a person live: connect / accept /
// message, skill endorsements (guidelines 2.3: "endorse specific skills
// displayed on another user's profile") and written recommendations.
// Opening someone's profile records a content_views row, which is what
// get_student_profile_views() counts for their analytics dashboard.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show AppColors, AppRadius, AppSpace, AppText, Pill, RoundedCard, SectionHeader;
import '../services/auth_error_mapper.dart';
import '../services/connections_service.dart';
import '../services/profile_service.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/time_labels.dart';
import 'chat_screen.dart';

class MemberProfileScreen extends StatefulWidget {
  const MemberProfileScreen({super.key, required this.profileId});

  final String profileId;

  @override
  State<MemberProfileScreen> createState() => _MemberProfileScreenState();
}

class _MemberProfileScreenState extends State<MemberProfileScreen> {
  /// Counted once per profile per app session, so opening the same profile
  /// five times in a demo doesn't inflate that person's view analytics.
  static final Set<String> _viewedThisSession = {};

  /// Guidelines 2.3: "Alumni, lecturers, mentors, supervisors, and employers
  /// may also provide short written recommendations".
  static const _recommenderRoles = {'alumni', 'business', 'administrator'};

  final _client = Supabase.instance.client;
  late final _connections = ConnectionsService(_client);

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _skills = [];
  List<Map<String, dynamic>> _endorsements = [];
  List<Map<String, dynamic>> _education = [];
  List<Map<String, dynamic>> _experience = [];
  List<Map<String, dynamic>> _projects = [];
  List<Map<String, dynamic>> _certifications = [];
  List<Map<String, dynamic>> _badges = [];
  List<Map<String, dynamic>> _recommendations = [];
  Map<String, dynamic>? _company;
  String _myRole = '';
  NetworkSnapshot _network = NetworkSnapshot(const []);

  bool _actionBusy = false;
  final Set<String> _skillBusy = {};

  String? get _me => _client.auth.currentUser?.id;
  bool get _isMe => _me == widget.profileId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = _me;
    if (me == null) return;
    final id = widget.profileId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        _client
            .from('profiles')
            .select('id, first_name, last_name, role, professional_headline, bio, career_interests, '
                'avatar_path, github_url, linkedin_url, website_url')
            .eq('id', id)
            .maybeSingle(),
        _client.from('skills').select('id, skill_name').eq('profile_id', id).order('created_at'),
        _client.from('endorsements').select('skill_id, endorser_id').eq('recipient_id', id),
        _client
            .from('education')
            .select('programme, campus, enrolment_year, graduation_year')
            .eq('profile_id', id)
            .order('enrolment_year', ascending: false),
        _client
            .from('work_experience')
            .select('title, organisation, description, start_date, end_date')
            .eq('profile_id', id),
        _client.from('projects').select('title, description, github_url, live_url').eq('profile_id', id),
        _client
            .from('certifications')
            .select('title, issuer, credential_url, date_earned')
            .eq('profile_id', id),
        _client
            .from('badges')
            .select('title, issuer, credential_url, date_earned')
            .eq('profile_id', id),
        _client
            .from('recommendations')
            .select('id, body, created_at, author_id, '
                'author:profiles!recommendations_author_id_fkey(first_name, last_name, role, '
                'professional_headline, avatar_path)')
            .eq('recipient_id', id)
            .order('created_at', ascending: false),
        _client
            .from('business_profiles')
            .select('company_name, industry, description, location, website, contact_email')
            .eq('profile_id', id)
            .maybeSingle(),
        _client.from('profiles').select('role').eq('id', me).single(),
        _connections.load(me),
      ]);
      if (!mounted) return;

      List<Map<String, dynamic>> rows(int i) => List<Map<String, dynamic>>.from(results[i] as List);
      setState(() {
        _profile = results[0] as Map<String, dynamic>?;
        _skills = rows(1);
        _endorsements = rows(2);
        _education = rows(3);
        _experience = rows(4);
        _projects = rows(5);
        _certifications = rows(6);
        _badges = rows(7);
        _recommendations = rows(8);
        _company = results[9] as Map<String, dynamic>?;
        _myRole = (results[10] as Map<String, dynamic>)['role'] as String? ?? '';
        _network = results[11] as NetworkSnapshot;
        _loading = false;
      });

      if (_profile != null && !_isMe && _viewedThisSession.add(id)) {
        unawaited(_client
            .from('content_views')
            .insert({'viewer_id': me, 'content_type': 'profile', 'content_id': id})
            .then((_) {}, onError: (_) {}));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AuthErrorMapper.fromAny(e);
      });
    }
  }

  Future<void> _primaryAction() async {
    final me = _me;
    if (me == null) return;
    final status = _network.statusWith(widget.profileId);
    if (status == RelationStatus.connected) {
      _openChat();
      return;
    }

    setState(() => _actionBusy = true);
    try {
      if (status == RelationStatus.none) {
        await _connections.sendRequest(me: me, personId: widget.profileId);
        _snack('Connection request sent.');
      } else if (status == RelationStatus.pendingIncoming) {
        await _connections.respond(connectionId: _network.edgeWith(widget.profileId)!.id, accept: true);
        _snack('You\'re now connected.');
      }
      final snapshot = await _connections.load(me);
      if (mounted) setState(() => _network = snapshot);
    } catch (e) {
      _snack(connectionErrorMessage(e));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  void _openChat() {
    final profile = _profile;
    if (profile == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(partnerId: widget.profileId, partner: PersonSummary.fromRow(profile)),
    ));
  }

  Future<void> _toggleEndorsement(String skillId, bool endorse) async {
    final me = _me;
    if (me == null || _skillBusy.contains(skillId)) return;
    setState(() => _skillBusy.add(skillId));
    try {
      if (endorse) {
        await _client
            .from('endorsements')
            .insert({'endorser_id': me, 'recipient_id': widget.profileId, 'skill_id': skillId});
      } else {
        await _client.from('endorsements').delete().eq('endorser_id', me).eq('skill_id', skillId);
      }
      if (!mounted) return;
      setState(() {
        if (endorse) {
          _endorsements = [..._endorsements, {'skill_id': skillId, 'endorser_id': me}];
        } else {
          _endorsements = _endorsements
              .where((e) => !(e['skill_id'] == skillId && e['endorser_id'] == me))
              .toList();
        }
      });
    } catch (e) {
      _snack(AuthErrorMapper.fromAny(e));
    } finally {
      if (mounted) setState(() => _skillBusy.remove(skillId));
    }
  }

  Future<void> _writeRecommendation(PersonSummary person) async {
    final me = _me;
    if (me == null) return;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _RecommendationDialog(firstName: person.firstName),
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      await _client
          .from('recommendations')
          .insert({'author_id': me, 'recipient_id': widget.profileId, 'body': text.trim()});
      _snack('Recommendation added to ${person.firstName.isEmpty ? 'their' : '${person.firstName}\'s'} profile.');
      await _load();
    } catch (e) {
      _snack(AuthErrorMapper.fromAny(e));
    }
  }

  Future<void> _launch(String raw) async {
    final uri = Uri.tryParse(ProfileService.normalizeUrl(raw));
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _snack('Could not open that link.');
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final person = profile == null ? null : PersonSummary.fromRow(profile);
    final error = _error;

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (error != null) {
      body = _centered(error, retry: true);
    } else if (profile == null || person == null) {
      body = _centered('This profile isn\'t available. The account may no longer be active.');
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.base),
          children: [
            _header(profile, person),
            if (!_isMe) ...[const SizedBox(height: AppSpace.md), _actions()],
            if (_company != null) ...[const SizedBox(height: AppSpace.lg), _companySection(_company!)],
            const SizedBox(height: AppSpace.lg),
            _skillsSection(),
            if (_experience.isNotEmpty) ...[const SizedBox(height: AppSpace.lg), _experienceSection()],
            if (_projects.isNotEmpty) ...[const SizedBox(height: AppSpace.lg), _projectsSection()],
            if (_certifications.isNotEmpty) ...[
              const SizedBox(height: AppSpace.lg),
              _certificationsSection(),
            ],
            if (_badges.isNotEmpty) ...[const SizedBox(height: AppSpace.lg), _badgesSection()],
            if (_education.isNotEmpty) ...[const SizedBox(height: AppSpace.lg), _educationSection()],
            const SizedBox(height: AppSpace.lg),
            _recommendationsSection(person),
            const SizedBox(height: AppSpace.xl),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(person?.name ?? 'Profile', style: AppText.headlineSm()),
      ),
      body: body,
    );
  }

  Widget _centered(String text, {bool retry = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center, style: AppText.bodyMd(color: AppColors.onSurfaceVariant)),
            if (retry) TextButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }

  Widget _header(Map<String, dynamic> profile, PersonSummary person) {
    final bio = (profile['bio'] as String?)?.trim() ?? '';
    final interests = (profile['career_interests'] as String?)?.trim() ?? '';
    final education = _education.isEmpty ? null : _education.first;
    final educationLine = education == null
        ? ''
        : [education['programme'], education['campus'], _years(education)]
            .whereType<Object>()
            .map((v) => v.toString())
            .where((v) => v.isNotEmpty)
            .join(' • ');
    final links = _links(profile);

    return RoundedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileAvatar(
                firstName: person.firstName,
                lastName: person.lastName,
                avatarPath: person.avatarPath,
                radius: 36,
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (person.roleLabel.isNotEmpty)
                      Pill(
                        text: person.roleLabel.toUpperCase(),
                        background: AppColors.secondaryContainer,
                        foreground: AppColors.onSecondaryContainer,
                      ),
                    const SizedBox(height: 6),
                    Text(person.name, style: AppText.headlineMd()),
                    if (person.headline.isNotEmpty)
                      Text(person.headline, style: AppText.bodyMd(color: AppColors.onSurfaceVariant)),
                    if (educationLine.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.school_outlined, size: 14, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              educationLine,
                              style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text(bio, style: AppText.bodyMd()),
          ],
          if (interests.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text('Career interests: $interests', style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
          ],
          if (links.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Wrap(spacing: 8, runSpacing: 8, children: links),
          ],
        ],
      ),
    );
  }

  String? _years(Map<String, dynamic> education) {
    final start = education['enrolment_year'];
    final end = education['graduation_year'];
    if (start == null && end == null) return null;
    return '${start ?? '?'}–${end ?? 'present'}';
  }

  List<Widget> _links(Map<String, dynamic> profile) {
    Widget link(String label, IconData icon, String url) => ActionChip(
          avatar: Icon(icon, size: 16, color: AppColors.secondary),
          label: Text(label),
          onPressed: () => _launch(url),
        );
    String? url(String key) {
      final value = (profile[key] as String?)?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    final github = url('github_url');
    final linkedin = url('linkedin_url');
    final website = url('website_url');
    return [
      if (github != null) link('GitHub', Icons.code, github),
      if (linkedin != null) link('LinkedIn', Icons.business_center_outlined, linkedin),
      if (website != null) link('Website', Icons.language, website),
    ];
  }

  Widget _actions() {
    final status = _network.statusWith(widget.profileId);
    final (label, icon, enabled) = switch (status) {
      RelationStatus.connected => ('Message', Icons.chat_bubble_outline, true),
      RelationStatus.pendingIncoming => ('Accept request', Icons.check, true),
      RelationStatus.pendingOutgoing => ('Request sent', Icons.schedule, false),
      RelationStatus.none => ('Connect', Icons.person_add_alt_1, true),
    };
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _actionBusy || !enabled ? null : _primaryAction,
            icon: _actionBusy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(icon, size: 18),
            label: Text(label),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
          ),
        ),
        if (status == RelationStatus.connected) ...[
          const SizedBox(width: AppSpace.sm),
          Pill(
            text: 'CONNECTED',
            icon: Icons.check,
            background: AppColors.successGreenBg,
            foreground: AppColors.successGreen,
          ),
        ],
      ],
    );
  }

  Widget _companySection(Map<String, dynamic> company) {
    String text(String key) => (company[key] as String?)?.trim() ?? '';
    final meta = [text('industry'), text('location')].where((v) => v.isNotEmpty).join(' • ');
    final website = text('website');
    final email = text('contact_email');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: 'Company'),
        RoundedCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text('company_name'), style: AppText.headlineSm()),
              if (meta.isNotEmpty) Text(meta, style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
              if (text('description').isNotEmpty) ...[
                const SizedBox(height: AppSpace.sm),
                Text(text('description'), style: AppText.bodyMd()),
              ],
              if (website.isNotEmpty || email.isNotEmpty) ...[
                const SizedBox(height: AppSpace.sm),
                Wrap(
                  spacing: 8,
                  children: [
                    if (website.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => _launch(website),
                        icon: const Icon(Icons.language, size: 16),
                        label: const Text('Website'),
                      ),
                    if (email.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => launchUrl(Uri(scheme: 'mailto', path: email)),
                        icon: const Icon(Icons.mail_outline, size: 16),
                        label: const Text('Email'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _skillsSection() {
    final me = _me;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: 'Skills'),
        if (_skills.isEmpty)
          Text('No skills listed yet.', style: AppText.bodySm(color: AppColors.onSurfaceVariant))
        else ...[
          if (!_isMe)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Text(
                'Tap a skill to endorse it.',
                style: AppText.bodySm(color: AppColors.onSurfaceVariant),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final skill in _skills) _skillChip(skill, me),
            ],
          ),
        ],
      ],
    );
  }

  Widget _skillChip(Map<String, dynamic> skill, String? me) {
    final id = skill['id'] as String;
    final name = skill['skill_name'] as String? ?? '';
    final count = _endorsements.where((e) => e['skill_id'] == id).length;
    final endorsedByMe =
        me != null && _endorsements.any((e) => e['skill_id'] == id && e['endorser_id'] == me);
    final label = count == 0 ? name : '$name • $count';

    if (_isMe) return Chip(label: Text(label));
    return FilterChip(
      label: Text(label),
      selected: endorsedByMe,
      tooltip: endorsedByMe ? 'Remove your endorsement' : 'Endorse $name',
      onSelected: _skillBusy.contains(id) ? null : (on) => _toggleEndorsement(id, on),
    );
  }

  Widget _entryCard({
    required IconData icon,
    required String title,
    String? subtitle,
    String? body,
    List<Widget> actions = const [],
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: RoundedCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(icon, size: 18, color: AppColors.secondary),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.labelLg()),
                  if (subtitle != null && subtitle.isNotEmpty)
                    Text(subtitle, style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                  if (body != null && body.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(body.trim(), style: AppText.bodySm()),
                  ],
                  if (actions.isNotEmpty) Wrap(spacing: 4, children: actions),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _experienceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: 'Experience'),
        for (final w in _experience)
          _entryCard(
            icon: Icons.work_outline,
            title: w['title'] as String? ?? '',
            subtitle: [w['organisation'] as String?, _range(w['start_date'], w['end_date'])]
                .whereType<String>()
                .where((v) => v.isNotEmpty)
                .join(' • '),
            body: w['description'] as String?,
          ),
      ],
    );
  }

  String? _range(Object? start, Object? end) {
    final from = monthYearLabel(start);
    final to = monthYearLabel(end);
    if (from == null && to == null) return null;
    return '${from ?? '?'} – ${to ?? 'Present'}';
  }

  Widget _projectsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: 'Projects'),
        for (final p in _projects)
          _entryCard(
            icon: Icons.terminal,
            title: p['title'] as String? ?? '',
            body: p['description'] as String?,
            actions: [
              if ((p['github_url'] as String?)?.trim().isNotEmpty ?? false)
                TextButton.icon(
                  onPressed: () => _launch(p['github_url'] as String),
                  icon: const Icon(Icons.code, size: 16),
                  label: const Text('Source'),
                ),
              if ((p['live_url'] as String?)?.trim().isNotEmpty ?? false)
                TextButton.icon(
                  onPressed: () => _launch(p['live_url'] as String),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Live'),
                ),
            ],
          ),
      ],
    );
  }

  Widget _certificationsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: 'Certifications'),
        for (final c in _certifications)
          _entryCard(
            icon: Icons.verified_outlined,
            title: c['title'] as String? ?? '',
            subtitle: [c['issuer'] as String?, monthYearLabel(c['date_earned'])]
                .whereType<String>()
                .where((v) => v.isNotEmpty)
                .join(' • '),
            actions: [
              if ((c['credential_url'] as String?)?.trim().isNotEmpty ?? false)
                TextButton.icon(
                  onPressed: () => _launch(c['credential_url'] as String),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('View credential'),
                ),
            ],
          ),
      ],
    );
  }

  Widget _badgesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: 'Badges'),
        for (final b in _badges)
          _entryCard(
            icon: Icons.military_tech_outlined,
            title: b['title'] as String? ?? '',
            subtitle: [b['issuer'] as String?, monthYearLabel(b['date_earned'])]
                .whereType<String>()
                .where((v) => v.isNotEmpty)
                .join(' • '),
            actions: [
              if ((b['credential_url'] as String?)?.trim().isNotEmpty ?? false)
                TextButton.icon(
                  onPressed: () => _launch(b['credential_url'] as String),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(_isCredly(b['credential_url'] as String) ? 'View on Credly' : 'View badge'),
                ),
            ],
          ),
      ],
    );
  }

  bool _isCredly(String url) => url.toLowerCase().contains('credly.com');

  Widget _educationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: 'Education'),
        for (final e in _education)
          _entryCard(
            icon: Icons.school_outlined,
            title: e['programme'] as String? ?? '',
            subtitle: [e['campus'] as String?, _years(e)]
                .whereType<String>()
                .where((v) => v.isNotEmpty)
                .join(' • '),
          ),
      ],
    );
  }

  Widget _recommendationsSection(PersonSummary person) {
    final canWrite = !_isMe && _recommenderRoles.contains(_myRole);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: 'Recommendations'),
        if (_recommendations.isEmpty)
          Text('No recommendations yet.', style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
        for (final r in _recommendations) _recommendationCard(r),
        if (canWrite) ...[
          const SizedBox(height: AppSpace.sm),
          OutlinedButton.icon(
            onPressed: () => _writeRecommendation(person),
            icon: const Icon(Icons.rate_review_outlined),
            label: Text('Recommend ${person.firstName.isEmpty ? 'this member' : person.firstName}'),
          ),
        ],
      ],
    );
  }

  Widget _recommendationCard(Map<String, dynamic> r) {
    final authorRow = r['author'];
    final author = authorRow is Map
        ? PersonSummary.fromRow({...Map<String, dynamic>.from(authorRow), 'id': r['author_id']})
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: RoundedCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.format_quote, color: AppColors.outline),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    r['body'] as String? ?? '',
                    style: AppText.bodyMd().copyWith(fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Row(
              children: [
                ProfileAvatar(
                  firstName: author?.firstName,
                  lastName: author?.lastName,
                  avatarPath: author?.avatarPath,
                  radius: 14,
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(author?.name ?? 'Former member', style: AppText.labelMd()),
                      if ((author?.subtitle ?? '').isNotEmpty)
                        Text(
                          author!.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecommendationDialog extends StatefulWidget {
  const _RecommendationDialog({required this.firstName});

  final String firstName;

  @override
  State<_RecommendationDialog> createState() => _RecommendationDialogState();
}

class _RecommendationDialogState extends State<_RecommendationDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.firstName.isEmpty ? 'this member' : widget.firstName;
    return AlertDialog(
      title: Text('Recommend $name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 4,
        maxLines: 8,
        maxLength: 600,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: 'How do you know $name, and what are they great at?',
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (_, value, __) => FilledButton(
            onPressed: value.text.trim().length < 20 ? null : () => Navigator.pop(context, value.text),
            child: const Text('Publish'),
          ),
        ),
      ],
    );
  }
}

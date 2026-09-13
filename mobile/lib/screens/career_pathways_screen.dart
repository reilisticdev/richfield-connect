// mobile/lib/screens/career_pathways_screen.dart
//
// Career pathway explorer (guidelines 2.5): where alumni who studied a
// programme have ended up, and the roles they held on the way. Opens on the
// viewer's own programme when alumni from it have shared their experience.

import 'package:flutter/material.dart';

import '../main.dart' show AppColors, AppRadius, AppSpace, AppText;
import '../services/auth_error_mapper.dart';
import '../services/career_pathway_service.dart';
import '../widgets/profile_avatar.dart';
import 'member_profile_screen.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _monthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

bool _sameText(String? a, String? b) => a != null && b != null && a.trim().toLowerCase() == b.trim().toLowerCase();

String? _findIn(List<String> options, String? value) {
  if (value == null) return null;
  for (final option in options) {
    if (_sameText(option, value)) return option;
  }
  return null;
}

class CareerPathwaysScreen extends StatefulWidget {
  const CareerPathwaysScreen({super.key, this.service});

  final CareerPathwayService? service;

  @override
  State<CareerPathwaysScreen> createState() => _CareerPathwaysScreenState();
}

class _CareerPathwaysScreenState extends State<CareerPathwaysScreen> {
  late final CareerPathwayService _service = widget.service ?? CareerPathwayService();
  final _search = TextEditingController();

  CareerPathways? _data;
  String? _error;
  bool _loading = true;
  String? _programme;
  String? _industry;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await _service.load();
      if (!mounted) return;
      setState(() {
        _programme = _data == null ? _findIn(data.programmes, data.myProgramme) : _findIn(data.programmes, _programme);
        _industry = _findIn(data.industries, _industry);
        _data = data;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final message = AuthErrorMapper.fromAny(e);
      if (_data != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
      setState(() {
        _error = message;
        _loading = false;
      });
    }
  }

  void _clearFilters() {
    _search.clear();
    setState(() {
      _programme = null;
      _industry = null;
      _query = '';
    });
  }

  List<AlumniPathway> _visible(CareerPathways data) {
    final q = _query.trim().toLowerCase();
    bool matchesQuery(AlumniPathway p) =>
        p.name.toLowerCase().contains(q) ||
        p.skills.any((s) => s.toLowerCase().contains(q)) ||
        p.roles.any((r) =>
            r.title.toLowerCase().contains(q) ||
            r.organisation.toLowerCase().contains(q) ||
            (r.industry ?? '').toLowerCase().contains(q));

    return [
      for (final p in data.pathways)
        if ((_programme == null || _sameText(p.programme, _programme)) &&
            (_industry == null || p.roles.any((r) => _sameText(r.industry, _industry))) &&
            (q.isEmpty || matchesQuery(p)))
          p,
    ];
  }

  void _openProfile(AlumniPathway pathway) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MemberProfileScreen(profileId: pathway.alumniId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Career pathways', style: AppText.headlineSm()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : data == null
              ? Center(
                  child: SingleChildScrollView(
                    child: _Message(
                      icon: Icons.cloud_off_outlined,
                      title: 'Couldn\'t load pathways',
                      body: _error ?? 'Please try again.',
                      actionLabel: 'Try again',
                      onAction: _load,
                    ),
                  ),
                )
              : RefreshIndicator(onRefresh: _load, child: _content(data)),
    );
  }

  Widget _content(CareerPathways data) {
    final visible = _visible(data);
    final myProgrammeListed = _findIn(data.programmes, data.myProgramme) != null;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpace.base, AppSpace.sm, AppSpace.base, AppSpace.xxl),
      children: [
        Text('Where Richfield graduates go', style: AppText.headlineMd()),
        const SizedBox(height: AppSpace.xs),
        Text(
          'Roles held by verified Richfield alumni, grouped by the programme they studied. Alumni who keep '
          'their education or experience private from you aren\'t shown.',
          style: AppText.bodySm(color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpace.base),
        if (data.pathways.isEmpty)
          const _Message(
            icon: Icons.route_outlined,
            title: 'No alumni pathways yet',
            body: 'Pathways appear when alumni, once a Richfield administrator has verified them, add work '
                'experience to their portfolio. Check back as more alumni join. If you are an alumnus, add '
                'your roles so students can see where your programme led.',
          )
        else ...[
          _filters(data),
          const SizedBox(height: AppSpace.base),
          if (data.myProgramme == null)
            _hint('Add your programme under Education in your portfolio and this page will open on alumni from '
                'your course.')
          else if (!myProgrammeListed)
            _hint('No alumni who studied ${data.myProgramme} have shared their experience yet, so every '
                'programme is shown.'),
          if (visible.isEmpty)
            _Message(
              icon: Icons.search_off,
              title: 'No pathways match',
              body: 'Try another programme, industry or search.',
              actionLabel: 'Clear filters',
              onAction: _clearFilters,
            )
          else ...[
            _summary(visible),
            const SizedBox(height: AppSpace.xl),
            Text(
              '${visible.length} ${visible.length == 1 ? 'pathway' : 'pathways'}',
              style: AppText.headlineSm(),
            ),
            const SizedBox(height: AppSpace.sm),
            for (final pathway in visible) ...[
              _PathwayCard(
                pathway: pathway,
                highlightIndustry: _industry,
                onOpen: () => _openProfile(pathway),
              ),
              const SizedBox(height: AppSpace.md),
            ],
          ],
        ],
      ],
    );
  }

  InputDecoration _fieldDecoration({String? label, String? hint, Widget? prefix, Widget? suffix}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      borderSide: BorderSide(color: AppColors.outlineVariant),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefix,
      suffixIcon: suffix,
      isDense: true,
      filled: true,
      fillColor: AppColors.surfaceContainerLowest,
      border: border,
      enabledBorder: border,
    );
  }

  Widget _filters(CareerPathways data) {
    final industries = data.industries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onChanged: (value) => setState(() => _query = value),
          decoration: _fieldDecoration(
            hint: 'Search roles, companies, industries or skills',
            prefix: const Icon(Icons.search),
            suffix: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        InputDecorator(
          decoration: _fieldDecoration(label: 'Programme'),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _programme,
              isExpanded: true,
              isDense: true,
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('All programmes')),
                for (final programme in data.programmes)
                  DropdownMenuItem<String?>(
                    value: programme,
                    child: Text(
                      _sameText(programme, data.myProgramme) ? '$programme (yours)' : programme,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _programme = value),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Text('Industry', style: AppText.labelMd(color: AppColors.onSurfaceVariant)),
        const SizedBox(height: AppSpace.xs),
        if (industries.isEmpty)
          Text(
            'Industries show here once alumni add one to their roles.',
            style: AppText.bodySm(color: AppColors.onSurfaceVariant),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _industryChip(null, 'Any industry'),
                for (final industry in industries) _industryChip(industry, industry),
              ],
            ),
          ),
      ],
    );
  }

  Widget _industryChip(String? value, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpace.sm),
      child: ChoiceChip(
        label: Text(label),
        selected: value == null ? _industry == null : _sameText(_industry, value),
        onSelected: (_) => setState(() => _industry = value),
      ),
    );
  }

  Widget _hint(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.base),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: AppColors.secondary),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text(text, style: AppText.bodySm())),
        ],
      ),
    );
  }

  static List<(String, int)> _top(Iterable<String> values, int limit) {
    final counts = <String, int>{};
    final labels = <String, String>{};
    for (final value in values) {
      final label = value.trim();
      if (label.isEmpty) continue;
      final key = label.toLowerCase();
      labels.putIfAbsent(key, () => label);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final keys = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return [for (final key in keys.take(limit)) (labels[key]!, counts[key]!)];
  }

  Widget _summary(List<AlumniPathway> visible) {
    final roles = [for (final p in visible) ...p.roles];
    final currentEmployers = [for (final r in roles) if (r.end == null && r.start != null) r.organisation];
    final employers = _top(currentEmployers.isNotEmpty ? currentEmployers : roles.map((r) => r.organisation), 5);
    final titles = _top(roles.map((r) => r.title), 5);
    final skills = _top([for (final p in visible) ...p.skills], 8);
    final organisationCount = _top(roles.map((r) => r.organisation), 1000).length;

    return Container(
      padding: const EdgeInsets.all(AppSpace.base),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _stat('${visible.length}', visible.length == 1 ? 'alumnus' : 'alumni'),
              _stat('${roles.length}', roles.length == 1 ? 'role' : 'roles'),
              _stat('$organisationCount', organisationCount == 1 ? 'organisation' : 'organisations'),
            ],
          ),
          const SizedBox(height: AppSpace.base),
          Text('Most common roles', style: AppText.labelLg()),
          const SizedBox(height: AppSpace.sm),
          for (final (label, count) in titles) _bar(label, count, titles.first.$2),
          const SizedBox(height: AppSpace.md),
          Text(currentEmployers.isNotEmpty ? 'Where they work now' : 'Where they have worked', style: AppText.labelLg()),
          const SizedBox(height: AppSpace.sm),
          for (final (label, count) in employers) _bar(label, count, employers.first.$2),
          if (skills.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text('Skills these alumni list', style: AppText.labelLg()),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                for (final (label, count) in skills)
                  Chip(visualDensity: VisualDensity.compact, label: Text(count > 1 ? '$label · $count' : label)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppText.headlineMd(color: AppColors.primary)),
          Text(label, style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _bar(String label, int count, int max) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodySm()),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: LinearProgressIndicator(
                value: max == 0 ? 0 : count / max,
                minHeight: 8,
                backgroundColor: AppColors.surfaceContainerHigh,
                valueColor: AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          SizedBox(
            width: 24,
            child: Text('$count', textAlign: TextAlign.end, style: AppText.labelMd()),
          ),
        ],
      ),
    );
  }
}

class _PathwayCard extends StatelessWidget {
  const _PathwayCard({required this.pathway, required this.onOpen, this.highlightIndustry});

  final AlumniPathway pathway;
  final VoidCallback onOpen;
  final String? highlightIndustry;

  static String _roleDetail(PathwayRole role) {
    final where = [role.organisation, if (role.industry != null) role.industry!].join(' · ');
    final start = role.start;
    if (start == null) return where;
    final end = role.end;
    return '$where\n${_monthYear(start)} – ${end == null ? 'present' : _monthYear(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final p = pathway;
    final studied = [
      if (p.graduationYear != null) 'Class of ${p.graduationYear}',
      if (p.campus != null) p.campus!,
    ].join(' · ');
    final latest = p.roles.isEmpty ? null : p.roles.last;
    final subtitle = p.headline ?? (latest == null ? null : '${latest.title} at ${latest.organisation}');

    return Material(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(AppSpace.base),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ProfileAvatar(firstName: p.firstName, lastName: p.lastName, avatarPath: p.avatarPath, radius: 22),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name, style: AppText.labelLg()),
                        if (subtitle != null)
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              _TimelineStep(
                icon: Icons.school_outlined,
                title: p.programme,
                detail: studied.isEmpty ? null : studied,
                accent: AppColors.secondary,
                isFirst: true,
                isLast: p.roles.isEmpty,
              ),
              for (var i = 0; i < p.roles.length; i++)
                _TimelineStep(
                  icon: p.roles[i].end == null && p.roles[i].start != null ? Icons.work : Icons.work_outline,
                  title: p.roles[i].title,
                  detail: _roleDetail(p.roles[i]),
                  accent: _sameText(p.roles[i].industry, highlightIndustry) ? AppColors.tertiary : AppColors.primary,
                  isFirst: false,
                  isLast: i == p.roles.length - 1,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.icon,
    required this.title,
    required this.accent,
    required this.isFirst,
    required this.isLast,
    this.detail,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final Color accent;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final line = AppColors.outlineVariant;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(width: 2, height: 4, color: isFirst ? Colors.transparent : line),
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), shape: BoxShape.circle),
                  child: Icon(icon, size: 15, color: accent),
                ),
                Expanded(child: Container(width: 2, color: isLast ? Colors.transparent : line)),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 7, bottom: isLast ? 0 : AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.labelMd()),
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(detail!, style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body, this.actionLabel, this.onAction});

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.base, vertical: AppSpace.xl),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.onSurfaceVariant),
          const SizedBox(height: AppSpace.sm),
          Text(title, textAlign: TextAlign.center, style: AppText.headlineSm()),
          const SizedBox(height: AppSpace.xs),
          Text(body, textAlign: TextAlign.center, style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpace.md),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

// mobile/lib/screens/privacy_settings_screen.dart
//
// Privacy & data (POPIA): what Richfield Connect keeps and why, consents, who
// can see each portfolio section, a copy of your data, and account deletion.
// Every control writes to the database, and migration 030 enforces it there.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart' show AppColors, AppRadius, AppSpace, AppText;
import '../services/auth_error_mapper.dart';
import '../services/privacy_service.dart';
import '../widgets/ai_consent_prompt.dart' show aiProcessingExplanation;

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _dateLabel(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key, this.service});

  final PrivacyService? service;

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  late final PrivacyService _service = widget.service ?? PrivacyService();

  PrivacySettings? _settings;
  String? _error;
  bool _loading = true;
  bool _consentSaving = false;
  final Set<ProfileSection> _sectionsSaving = {};
  bool _exporting = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await _service.load();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final message = AuthErrorMapper.fromAny(e);
      if (_settings != null) _toast(message);
      setState(() {
        _error = message;
        _loading = false;
      });
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setAiConsent(bool allow) async {
    setState(() => _consentSaving = true);
    try {
      if (allow) {
        await _service.grant(ConsentType.aiProcessing);
      } else {
        await _service.withdraw(ConsentType.aiProcessing);
      }
      await _load();
    } catch (e) {
      if (mounted) _toast(AuthErrorMapper.fromAny(e));
    } finally {
      if (mounted) setState(() => _consentSaving = false);
    }
  }

  Future<void> _toggleAudience(ProfileSection section, Audience audience) async {
    final settings = _settings;
    if (settings == null || _sectionsSaving.contains(section)) return;
    final next = {...settings.audiencesFor(section)};
    if (!next.remove(audience)) next.add(audience);

    setState(() {
      _sectionsSaving.add(section);
      _settings = settings.withAudiences(section, next);
    });
    try {
      await _service.setAudiences(section, next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _settings = settings);
      _toast(AuthErrorMapper.fromAny(e));
    } finally {
      if (mounted) setState(() => _sectionsSaving.remove(section));
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final data = await _service.exportMyData();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _DataExportView(data: data),
      ));
    } catch (e) {
      if (mounted) _toast(AuthErrorMapper.fromAny(e));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _delete() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'Your account and everything linked to it are removed straight away, and this can\'t be undone. '
          'If you want a copy of your data, get it first.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    final confirmed = await showDialog<bool>(context: context, builder: (_) => const _TypeToConfirmDialog());
    if (confirmed != true || !mounted) return;

    final navigator = Navigator.of(context);
    setState(() => _deleting = true);
    try {
      await _service.deleteAccount();
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      _toast(AuthErrorMapper.fromAny(e));
      return;
    }
    navigator.popUntil((route) => route.isFirst);
    await _service.signOutAfterDeletion();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Privacy & data', style: AppText.headlineSm()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : settings == null
              ? _LoadError(message: _error ?? 'Couldn\'t load your privacy settings.', onRetry: _load)
              : AbsorbPointer(
                  absorbing: _deleting,
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(AppSpace.base, AppSpace.sm, AppSpace.base, AppSpace.xxl),
                      children: [
                        const _PopiaNotice(),
                        const SizedBox(height: AppSpace.xl),
                        _heading('Consent'),
                        _aiConsentCard(settings),
                        const SizedBox(height: AppSpace.sm),
                        _registrationConsentCard(settings),
                        const SizedBox(height: AppSpace.xl),
                        _heading('Who can see your profile'),
                        Text(
                          'Signed-in members can see your name, photo, headline, bio and links. Choose who '
                          'else sees each section below. You always see your own.',
                          style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                        ),
                        const SizedBox(height: AppSpace.sm),
                        _visibilityCard(settings),
                        const SizedBox(height: AppSpace.xl),
                        _heading('Your data'),
                        _exportCard(),
                        if (!settings.isAdministrator) ...[
                          const SizedBox(height: AppSpace.base),
                          _deleteCard(),
                        ],
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: Text(text, style: AppText.headlineSm()),
      );

  Widget _card({required Widget child, Color? borderColor}) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: borderColor ?? AppColors.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: child,
      );

  Widget _aiConsentCard(PrivacySettings settings) {
    final latest = settings.latest(ConsentType.aiProcessing);
    final granted = latest?.isActive ?? false;
    final status = latest == null
        ? 'Not allowed'
        : granted
            ? 'Allowed on ${_dateLabel(latest.grantedAt)}'
            : 'Withdrawn on ${_dateLabel(latest.withdrawnAt!)}';

    return _card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.base, AppSpace.sm, AppSpace.sm, AppSpace.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_outlined, color: AppColors.primary, size: 20),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: Text('Career AI assistant', style: AppText.labelLg())),
                Switch(value: granted, onChanged: _consentSaving ? null : _setAiConsent),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: AppSpace.sm),
              child: Text(
                '$aiProcessingExplanation Turning this off stops the assistant and CV import from sending anything.',
                style: AppText.bodySm(color: AppColors.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              status,
              style: AppText.labelMd(color: granted ? AppColors.successGreen : AppColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _registrationConsentCard(PrivacySettings settings) {
    final record = settings.latest(ConsentType.registration);
    final given = record == null
        ? 'No consent is on record, because this account was created before signup recorded it.'
        : 'Given at signup on ${_dateLabel(record.grantedAt)}.';
    final withdraw = settings.isAdministrator
        ? ' Staff accounts are managed by Richfield.'
        : ' To withdraw it, delete your account below.';

    return _card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.base),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.assignment_turned_in_outlined, color: AppColors.secondary, size: 20),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Keeping your account details', style: AppText.labelLg()),
                  const SizedBox(height: AppSpace.xs),
                  Text('$given$withdraw', style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _visibilityCard(PrivacySettings settings) {
    return _card(
      child: Column(
        children: [
          for (final section in ProfileSection.values) ...[
            if (section != ProfileSection.values.first)
              Divider(height: 1, color: AppColors.outlineVariant.withValues(alpha: 0.5)),
            _visibilityRow(section, settings.audiencesFor(section)),
          ],
        ],
      ),
    );
  }

  Widget _visibilityRow(ProfileSection section, Set<Audience> audiences) {
    final saving = _sectionsSaving.contains(section);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.base, vertical: AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(section.label, style: AppText.labelLg())),
              if (saving)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Text(_audienceSummary(audiences), style: AppText.labelMd(color: AppColors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [
              for (final audience in Audience.values)
                FilterChip(
                  label: Text(audience.label),
                  selected: audiences.contains(audience),
                  onSelected: saving ? null : (_) => _toggleAudience(section, audience),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _audienceSummary(Set<Audience> audiences) {
    if (audiences.length == Audience.values.length) return 'All members';
    if (audiences.isEmpty) return 'Only you';
    final labels = [
      for (final a in Audience.values)
        if (audiences.contains(a)) a.label,
    ];
    return labels.length == 1 ? '${labels.first} only' : '${labels[0]} and ${labels[1].toLowerCase()}';
  }

  Widget _exportCard() => _card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Get a copy of your data', style: AppText.labelLg()),
              const SizedBox(height: AppSpace.xs),
              Text(
                'Everything Richfield Connect holds about you: your account and signup details, profile, '
                'portfolio, posts, connections, messages, applications, consents and a list of the files '
                'you uploaded.',
                style: AppText.bodySm(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpace.md),
              OutlinedButton.icon(
                onPressed: _exporting ? null : _export,
                icon: _exporting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.data_object),
                label: Text(_exporting ? 'Preparing…' : 'Get my data'),
              ),
            ],
          ),
        ),
      );

  Widget _deleteCard() => _card(
        borderColor: AppColors.error.withValues(alpha: 0.5),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Delete my account', style: AppText.labelLg(color: AppColors.error)),
              const SizedBox(height: AppSpace.xs),
              Text(
                'Removes your account and everything linked to it: profile and portfolio, posts, comments and '
                'reactions, connections, messages (for both people in the conversation), applications, '
                'listings and the applications to them, endorsements and recommendations, consents and '
                'uploaded files. Reports you filed are kept for moderation without your name.',
                style: AppText.bodySm(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpace.md),
              FilledButton.icon(
                onPressed: _deleting ? null : _delete,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: AppColors.onError,
                ),
                icon: _deleting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.delete_forever_outlined),
                label: Text(_deleting ? 'Deleting…' : 'Delete my account'),
              ),
            ],
          ),
        ),
      );
}

class _PopiaNotice extends StatelessWidget {
  const _PopiaNotice();

  static const _sections = <(String, String)>[
    (
      'What we keep',
      'Your account (name, email address and role), the profile and portfolio sections you fill in, what '
          'you post, comment on and react to, your connections and messages, applications and listings, and '
          'the details you gave at signup: programme, campus and years, your student number if you registered '
          'as alumni, and company details if you registered as an employer. We also record which posts you '
          'view and, for employers, which skills you search for, to build the analytics dashboards.',
    ),
    (
      'Why',
      'To run your account and portfolio, connect you with other members, match students to opportunities, '
          'verify alumni and employers, keep the platform safe, and send you notifications.',
    ),
    (
      'Who can see it',
      'Signed-in members can see your name, photo, headline, bio and links, and the sections you allow '
          'below. Your posts and comments are public. Messages are visible only to you and the person you are '
          'talking to. Employers see the applications you send them. Richfield administrators can see accounts '
          'so they can verify, moderate and support them.',
    ),
    (
      'Where it is processed',
      'Your information is stored with Supabase in Frankfurt, Germany. Emails are sent through Resend and push '
          'notifications through Google Firebase. If you allow the Career AI assistant, your profile summary '
          'and what you type or paste into it are sent to Google\'s Gemini service. These providers may '
          'process information outside South Africa.',
    ),
    (
      'How long we keep it',
      'For as long as your account is open. Deleting your account removes your records from the live '
          'database straight away; copies in routine database backups last only until those backups expire.',
    ),
    (
      'Your rights',
      'You can get a copy of your information, correct it by editing your profile, withdraw consent, object '
          'to how it is used, and have your account deleted. If you are unhappy with how your information is '
          'handled, contact Richfield, and you can also complain to the Information Regulator (South Africa).',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpace.base, vertical: AppSpace.xs),
          childrenPadding: const EdgeInsets.fromLTRB(AppSpace.base, 0, AppSpace.base, AppSpace.base),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          leading: Icon(Icons.privacy_tip_outlined, color: AppColors.primary),
          title: Text('How we use your information', style: AppText.labelLg()),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Text(
              'Richfield is responsible for your personal information on Richfield Connect under the Protection '
              'of Personal Information Act (POPIA). Tap to read what we keep and why.',
              style: AppText.bodySm(color: AppColors.onSurfaceVariant),
            ),
          ),
          children: [
            for (final (title, body) in _sections) ...[
              const SizedBox(height: AppSpace.md),
              Text(title, style: AppText.labelMd()),
              const SizedBox(height: 2),
              Text(body, style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

class _DataExportView extends StatelessWidget {
  const _DataExportView({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final pretty = const JsonEncoder.withIndent('  ').convert(data);
    final counts = [
      for (final entry in data.entries)
        if (entry.value is List && (entry.value as List).isNotEmpty)
          '${entry.key.replaceAll('_', ' ')}: ${(entry.value as List).length}',
    ];

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Your data', style: AppText.headlineSm()),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: pretty));
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Copied to the clipboard.')));
              }
            },
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('Copy all'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.base),
        children: [
          Text(
            'Everything Richfield Connect holds about you, as JSON. Copy it to keep it or send it elsewhere.',
            style: AppText.bodySm(color: AppColors.onSurfaceVariant),
          ),
          if (counts.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [for (final label in counts) Chip(label: Text(label))],
            ),
          ],
          const SizedBox(height: AppSpace.md),
          Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: SelectableText(
              pretty,
              style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeToConfirmDialog extends StatefulWidget {
  const _TypeToConfirmDialog();

  @override
  State<_TypeToConfirmDialog> createState() => _TypeToConfirmDialogState();
}

class _TypeToConfirmDialogState extends State<_TypeToConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller.text.trim() == 'DELETE';
    return AlertDialog(
      title: const Text('Type DELETE to confirm'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This is the last step. Your account will be deleted as soon as you confirm.'),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'DELETE', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: ready ? () => Navigator.pop(context, true) : null,
          style: FilledButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: AppColors.onError),
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 40, color: AppColors.onSurfaceVariant),
            const SizedBox(height: AppSpace.sm),
            Text(message, textAlign: TextAlign.center, style: AppText.bodyMd(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: AppSpace.md),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

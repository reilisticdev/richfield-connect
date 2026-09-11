// mobile/lib/screens/cv_import_screen.dart
//
// NLP-assisted profile building from a CV or free text (rubric 8.3, and part
// of the section 6 profile assistant). The user pastes CV text or describes
// their experience in their own words; /api/parse-cv has Gemini extract
// name, headline, skills and an education summary as schema-enforced JSON;
// the user reviews every field before anything is written.
//
// Review-before-write is deliberate. A model can misread a CV, and silently
// overwriting a headline the user wrote themselves is worse than asking them
// to tick a box. Current values are shown beside extracted ones, and a field
// that is already filled in starts unticked.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart' show AppColors, AppRadius, AppSpace, AppText;
import '../services/ai_service.dart';
import '../services/auth_error_mapper.dart';
import '../services/profile_context_service.dart';
import '../services/profile_service.dart';

class CvImportScreen extends StatefulWidget {
  const CvImportScreen({super.key});

  @override
  State<CvImportScreen> createState() => _CvImportScreenState();
}

class _CvImportScreenState extends State<CvImportScreen> {
  static const _maxChars = 15000;

  final _client = Supabase.instance.client;
  late final _profileService = ProfileService(_client);
  late final _contextService = ProfileContextService(_client);
  final _ai = AiService();
  final _cv = TextEditingController();

  bool _parsing = false;
  bool _saving = false;
  String? _error;

  /// Null until an extraction has succeeded; the review section keys off it.
  ProfileContext? _ctx;

  String? _firstName;
  String? _lastName;
  String? _headline;
  String? _education;
  List<String> _skills = [];

  bool _useName = false;
  bool _useHeadline = false;
  bool _useEducation = false;
  final Set<String> _pickedSkills = {};

  @override
  void dispose() {
    _cv.dispose();
    super.dispose();
  }

  Future<void> _extract() async {
    final text = _cv.text.trim();
    if (text.length < 30) {
      setState(() => _error = 'Paste a bit more — at least a few lines about your studies or experience.');
      return;
    }
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _error = 'Your session has expired. Sign in again.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _parsing = true;
      _error = null;
    });

    try {
      final results = await Future.wait<Object>([
        _ai.parseCv(text),
        _contextService.load(userId),
      ]);
      if (!mounted) return;

      final parsed = results[0] as Map<String, dynamic>;
      final ctx = results[1] as ProfileContext;

      String? clean(Object? value) {
        final s = (value as String?)?.trim();
        return (s == null || s.isEmpty) ? null : s;
      }

      final skills = <String>[];
      for (final raw in (parsed['skills'] as List? ?? const []).whereType<String>()) {
        final name = raw.trim();
        if (name.isNotEmpty && !skills.any((s) => s.toLowerCase() == name.toLowerCase())) {
          skills.add(name);
        }
      }
      final have = ctx.skillNames.map((s) => s.toLowerCase()).toSet();

      setState(() {
        _parsing = false;
        _ctx = ctx;
        _firstName = clean(parsed['first_name']);
        _lastName = clean(parsed['last_name']);
        _headline = clean(parsed['professional_headline']);
        _education = clean(parsed['education_summary']);
        _skills = skills;

        // Pre-tick only what fills a gap — never pre-tick an overwrite.
        _useName = (_firstName != null || _lastName != null) && ctx.firstName.isEmpty;
        _useHeadline = _headline != null && !ctx.has('professional_headline');
        _useEducation = _education != null && !ctx.has('bio');
        _pickedSkills
          ..clear()
          ..addAll(skills.where((s) => !have.contains(s.toLowerCase())));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _parsing = false;
        _error = e is AiServiceException ? e.message : AuthErrorMapper.fromAny(e);
      });
    }
  }

  Future<void> _apply() async {
    final userId = _client.auth.currentUser?.id;
    final ctx = _ctx;
    if (userId == null || ctx == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // education_summary has no structured column (see AiService.parseCv),
      // so it goes into the About text — appended, never replacing it.
      String? bio;
      final education = _education;
      if (_useEducation && education != null) {
        final current = ctx.text('bio');
        bio = current.isEmpty ? education : '$current\n\n$education';
      }

      if (_useName || _useHeadline || bio != null) {
        await _profileService.updateOwnProfile(
          userId: userId,
          firstName: _useName ? _firstName : null,
          lastName: _useName ? _lastName : null,
          professionalHeadline: _useHeadline ? _headline : null,
          bio: bio,
        );
      }

      final added = _pickedSkills.isEmpty
          ? const <String>[]
          : await _profileService.addSkills(userId: userId, names: _pickedSkills);

      if (!mounted) return;
      final changes = [
        if (_useName) 'name',
        if (_useHeadline) 'headline',
        if (bio != null) 'About section',
        if (added.isNotEmpty) '${added.length} skill${added.length == 1 ? '' : 's'}',
      ];
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(changes.isEmpty ? 'Nothing new to add.' : 'Updated your ${changes.join(', ')}.'),
      ));
      Navigator.of(context).pop(changes.isNotEmpty);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = AuthErrorMapper.fromAny(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = _ctx;
    final anythingPicked = _useName || _useHeadline || _useEducation || _pickedSkills.isNotEmpty;
    final locked = _parsing || _saving;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Import from CV', style: AppText.headlineSm()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.base),
        children: [
          Text('Let AI read your CV', style: AppText.headlineMd()),
          const SizedBox(height: 4),
          Text(
            'Paste your CV, or describe your studies, skills and experience in your own words. '
            'The assistant pulls out a headline, skills and education — you choose what gets saved.',
            style: AppText.bodyMd(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpace.base),
          TextField(
            controller: _cv,
            enabled: !locked,
            minLines: 8,
            maxLines: 14,
            maxLength: _maxChars,
            decoration: InputDecoration(
              hintText: 'e.g. BSc IT student at Richfield (2024–2026). Built a Flutter app for…',
              filled: true,
              fillColor: AppColors.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.privacy_tip_outlined, size: 14, color: AppColors.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'This text is sent to Richfield Connect\'s AI service (Google Gemini) only to extract '
                  'these fields. Nothing is saved to your profile until you tap Apply.',
                  style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          OutlinedButton.icon(
            onPressed: locked ? null : _extract,
            icon: _parsing ? _spinner() : const Icon(Icons.auto_awesome),
            label: Text(_parsing
                ? 'Reading your CV…'
                : (ctx == null ? 'Extract with AI' : 'Extract again')),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 16, color: AppColors.error),
                const SizedBox(width: 6),
                Expanded(child: Text(_error!, style: AppText.bodySm(color: AppColors.error))),
              ],
            ),
          ],
          if (ctx != null) ..._review(ctx),
          if (ctx != null) ...[
            const SizedBox(height: AppSpace.lg),
            ElevatedButton.icon(
              onPressed: locked || !anythingPicked ? null : _apply,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
              ),
              icon: _saving ? _spinner(onPrimary: true) : const Icon(Icons.check),
              label: Text(_saving ? 'Saving…' : 'Apply to my profile'),
            ),
          ],
          const SizedBox(height: AppSpace.xl),
        ],
      ),
    );
  }

  List<Widget> _review(ProfileContext ctx) {
    final have = ctx.skillNames.map((s) => s.toLowerCase()).toSet();
    final extractedName = [_firstName, _lastName].whereType<String>().join(' ');
    final currentName = [ctx.firstName, ctx.text('last_name')].where((s) => s.isNotEmpty).join(' ');

    return [
      const SizedBox(height: AppSpace.lg),
      Text('Review what the AI found', style: AppText.headlineSm()),
      const SizedBox(height: AppSpace.sm),
      if (extractedName.isNotEmpty)
        _fieldTile(
          title: 'Name',
          extracted: extractedName,
          current: currentName,
          value: _useName,
          onChanged: (v) => setState(() => _useName = v),
        ),
      if (_headline != null)
        _fieldTile(
          title: 'Headline',
          extracted: _headline!,
          current: ctx.text('professional_headline'),
          value: _useHeadline,
          onChanged: (v) => setState(() => _useHeadline = v),
        ),
      if (_education != null)
        _fieldTile(
          title: 'Education (added to your About section)',
          extracted: _education!,
          current: ctx.text('bio'),
          currentNote: 'Added below your existing About text.',
          value: _useEducation,
          onChanged: (v) => setState(() => _useEducation = v),
        ),
      const SizedBox(height: AppSpace.sm),
      Text('Skills', style: AppText.labelLg()),
      const SizedBox(height: 6),
      if (_skills.isEmpty)
        Text('No skills found in that text.', style: AppText.bodySm(color: AppColors.onSurfaceVariant))
      else
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final skill in _skills)
              if (have.contains(skill.toLowerCase()))
                Chip(
                  avatar: Icon(Icons.check, size: 16, color: AppColors.successGreen),
                  label: Text('$skill (already listed)'),
                )
              else
                FilterChip(
                  label: Text(skill),
                  selected: _pickedSkills.contains(skill),
                  onSelected: _saving
                      ? null
                      : (on) => setState(() {
                            if (on) {
                              _pickedSkills.add(skill);
                            } else {
                              _pickedSkills.remove(skill);
                            }
                          }),
                ),
          ],
        ),
    ];
  }

  Widget _fieldTile({
    required String title,
    required String extracted,
    required String current,
    String? currentNote,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: CheckboxListTile(
        value: value,
        onChanged: _saving ? null : (v) => onChanged(v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(title, style: AppText.labelMd(color: AppColors.onSurfaceVariant)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(extracted, style: AppText.bodyMd()),
            if (current.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                currentNote ?? 'Replaces: $current',
                style: AppText.bodySm(color: AppColors.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _spinner({bool onPrimary = false}) => SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: onPrimary ? AppColors.onPrimary : AppColors.primary,
        ),
      );
}

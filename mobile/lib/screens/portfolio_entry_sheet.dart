// mobile/lib/screens/portfolio_entry_sheet.dart
//
// One bottom-sheet form for every section a member writes on their own
// portfolio. The fields marked required are exactly the tables' NOT NULL
// columns — education needs programme, campus and start year;
// work_experience and leadership_roles need an organisation; projects,
// certifications, badges and achievements only a title — so a save can't
// fail on a constraint the form never mentioned.

import 'package:flutter/material.dart';

import '../main.dart' show AppColors, AppRadius, AppSpace, AppText;
import '../services/auth_error_mapper.dart';
import '../services/portfolio_service.dart';
import '../services/profile_service.dart';
import '../widgets/time_labels.dart';

enum _Kind { text, multiline, url, year, date }

class _Field {
  const _Field(this.column, this.label, {this.kind = _Kind.text, this.required = false, this.hint});

  final String column;
  final String label;
  final _Kind kind;
  final bool required;
  final String? hint;
}

const _titles = {
  PortfolioSection.education: 'Add education',
  PortfolioSection.experience: 'Add experience',
  PortfolioSection.projects: 'Add a project',
  PortfolioSection.certifications: 'Add a certification',
  PortfolioSection.badges: 'Add a badge',
  PortfolioSection.achievements: 'Add an achievement',
  PortfolioSection.leadership: 'Add a leadership role',
};

const _fields = <PortfolioSection, List<_Field>>{
  PortfolioSection.education: [
    _Field('programme', 'Programme', required: true, hint: 'e.g. BSc Information Technology'),
    _Field('campus', 'Campus', required: true, hint: 'e.g. Braamfontein'),
    _Field('enrolment_year', 'Year started', kind: _Kind.year, required: true),
    _Field('graduation_year', 'Year of graduation', kind: _Kind.year, hint: 'Expected year is fine'),
  ],
  PortfolioSection.experience: [
    _Field('title', 'Job title', required: true),
    _Field('organisation', 'Organisation', required: true),
    _Field('industry', 'Industry', hint: 'e.g. Software, Banking, Retail'),
    _Field('description', 'What you did', kind: _Kind.multiline),
    _Field('start_date', 'Start date', kind: _Kind.date),
    _Field('end_date', 'End date', kind: _Kind.date, hint: 'Leave empty if you still work here'),
  ],
  PortfolioSection.projects: [
    _Field('title', 'Project name', required: true),
    _Field('description', 'What it does', kind: _Kind.multiline),
    _Field('github_url', 'Source code link', kind: _Kind.url, hint: 'github.com/you/project'),
    _Field('live_url', 'Live demo link', kind: _Kind.url),
  ],
  PortfolioSection.certifications: [
    _Field('title', 'Certification', required: true),
    _Field('issuer', 'Issued by'),
    _Field('credential_url', 'Credential link', kind: _Kind.url),
    _Field('date_earned', 'Date earned', kind: _Kind.date),
  ],
  PortfolioSection.badges: [
    _Field('title', 'Badge', required: true, hint: 'e.g. AWS Cloud Practitioner'),
    _Field('issuer', 'Issued by', hint: 'e.g. Credly, Microsoft Learn, Google'),
    _Field('credential_url', 'Badge link', kind: _Kind.url, hint: 'credly.com/badges/…'),
    _Field('date_earned', 'Date earned', kind: _Kind.date),
  ],
  PortfolioSection.achievements: [
    _Field('title', 'Achievement', required: true, hint: "e.g. Dean's list 2025, Hackathon winner"),
    _Field('description', 'What it was for', kind: _Kind.multiline),
    _Field('date_earned', 'Date received', kind: _Kind.date),
  ],
  PortfolioSection.leadership: [
    _Field('role_title', 'Role', required: true, hint: 'e.g. Class representative'),
    _Field('organisation', 'Organisation', required: true),
    _Field('description', 'What you were responsible for', kind: _Kind.multiline),
  ],
};

/// Opens the form for [section]. [onSave] performs the insert; the sheet
/// stays open with the error shown if it throws. Resolves true once saved.
Future<bool> showPortfolioEntrySheet(
  BuildContext context, {
  required PortfolioSection section,
  required Future<void> Function(Map<String, dynamic> values) onSave,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceContainerLowest,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => _PortfolioEntrySheet(section: section, onSave: onSave),
  );
  return saved ?? false;
}

class _PortfolioEntrySheet extends StatefulWidget {
  const _PortfolioEntrySheet({required this.section, required this.onSave});

  final PortfolioSection section;
  final Future<void> Function(Map<String, dynamic> values) onSave;

  @override
  State<_PortfolioEntrySheet> createState() => _PortfolioEntrySheetState();
}

class _PortfolioEntrySheetState extends State<_PortfolioEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  late final List<_Field> _spec = _fields[widget.section]!;
  late final Map<String, TextEditingController> _text = {
    for (final f in _spec)
      if (f.kind != _Kind.date) f.column: TextEditingController(),
  };
  final Map<String, DateTime?> _dates = {};

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate(_Field field) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dates[field.column] ?? now,
      firstDate: DateTime(1970),
      lastDate: DateTime(now.year + 6, 12, 31),
    );
    if (picked != null && mounted) setState(() => _dates[field.column] = picked);
  }

  String? _validate(_Field field, String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return field.required ? '${field.label} is required.' : null;
    switch (field.kind) {
      case _Kind.url:
        return ProfileService.validateOptionalUrl(value, field.label);
      case _Kind.year:
        final year = int.tryParse(value);
        final latest = DateTime.now().year + 8;
        if (year == null || year < 1970 || year > latest) {
          return 'Enter a year between 1970 and $latest.';
        }
        return null;
      case _Kind.text:
      case _Kind.multiline:
      case _Kind.date:
        return null;
    }
  }

  /// Empty optional fields are left out rather than sent as '' — an empty
  /// string in a date or integer column is a Postgres error, not a blank.
  Map<String, dynamic> _values() {
    final values = <String, dynamic>{};
    for (final f in _spec) {
      if (f.kind == _Kind.date) {
        final date = _dates[f.column];
        if (date != null) values[f.column] = _isoDate(date);
        continue;
      }
      final text = _text[f.column]!.text.trim();
      if (text.isEmpty) continue;
      values[f.column] = switch (f.kind) {
        _Kind.year => int.parse(text),
        _Kind.url => ProfileService.normalizeUrl(text),
        _ => text,
      };
    }
    return values;
  }

  String? _crossFieldProblem(Map<String, dynamic> values) {
    final started = values['enrolment_year'] as int?;
    final graduated = values['graduation_year'] as int?;
    if (started != null && graduated != null && graduated < started) {
      return "Graduation year can't be before the year you started.";
    }
    final from = _dates['start_date'];
    final to = _dates['end_date'];
    if (from != null && to != null && to.isBefore(from)) {
      return "End date can't be before the start date.";
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final values = _values();
    final problem = _crossFieldProblem(values);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(values);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = AuthErrorMapper.fromAny(e);
      });
    }
  }

  InputDecoration _decoration(_Field field, {Widget? suffix}) => InputDecoration(
        labelText: field.required ? '${field.label} *' : field.label,
        hintText: field.kind == _Kind.date ? null : field.hint,
        helperText: field.kind == _Kind.date ? field.hint : null,
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide.none,
        ),
      );

  Widget _textField(_Field field) {
    final multiline = field.kind == _Kind.multiline;
    return TextFormField(
      controller: _text[field.column],
      validator: (value) => _validate(field, value),
      minLines: multiline ? 2 : 1,
      maxLines: multiline ? 5 : 1,
      keyboardType: switch (field.kind) {
        _Kind.year => TextInputType.number,
        _Kind.url => TextInputType.url,
        _Kind.multiline => TextInputType.multiline,
        _ => TextInputType.text,
      },
      autocorrect: field.kind != _Kind.url,
      textCapitalization:
          field.kind == _Kind.url || field.kind == _Kind.year ? TextCapitalization.none : TextCapitalization.sentences,
      decoration: _decoration(field),
    );
  }

  Widget _dateField(_Field field) {
    final date = _dates[field.column];
    return InkWell(
      onTap: _saving ? null : () => _pickDate(field),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InputDecorator(
        isEmpty: date == null,
        decoration: _decoration(
          field,
          suffix: date == null
              ? Icon(Icons.calendar_today_outlined, size: 18)
              : IconButton(
                  tooltip: 'Clear ${field.label.toLowerCase()}',
                  onPressed: () => setState(() => _dates[field.column] = null),
                  icon: Icon(Icons.close, size: 18),
                ),
        ),
        child: Text(
          date == null ? '' : '${date.day} ${monthYearLabel(_isoDate(date))}',
          style: AppText.bodyMd(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(AppSpace.base),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_titles[widget.section]!, style: AppText.headlineSm()),
                SizedBox(height: AppSpace.md),
                for (final field in _spec)
                  Padding(
                    padding: EdgeInsets.only(bottom: AppSpace.md),
                    child: field.kind == _Kind.date ? _dateField(field) : _textField(field),
                  ),
                if (_error != null)
                  Padding(
                    padding: EdgeInsets.only(bottom: AppSpace.sm),
                    child: Text(_error!, style: AppText.bodySm(color: AppColors.error)),
                  ),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)),
                  child: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

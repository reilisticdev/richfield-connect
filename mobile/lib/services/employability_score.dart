// mobile/lib/services/employability_score.dart
//
// One 0-100 number for the Student dashboard, with a hint that names what
// would lift it. Guidelines 2.3 lists the portfolio evidence employers are
// meant to see: skills, education, experience, projects, certifications, a
// headline, a CV, public links and badges. Nine facts, equal weight.
//
// The first six are exactly the criteria get_student_completeness() scores
// (migration 018: EXISTS per table, headline present), so the score agrees
// with the "% complete vs your programme" comparison on everything they
// share. They are computed here from the rows ProfileContext already
// loads rather than read back from the RPC for two reasons: the RPC
// returns NULL for a student with no education row (its peer CTE joins
// education), which is every newly registered account; and it returns one
// percentage, not which items are missing, so it can't drive the hint.
//
// The three extras are the evidence the RPC predates: a CV on file
// (profiles.cv_path, migration 038), at least one public link, and at
// least one badge (badges table, Portfolio "Badges" section).

import 'profile_context_service.dart';

class EmployabilityItem {
  const EmployabilityItem({required this.key, required this.label, required this.done, required this.action});

  final String key;

  /// Short noun for lists ("CV on file").
  final String label;
  final bool done;

  /// Imperative, lower-case start, for the hint sentence ("upload your CV").
  final String action;
}

class EmployabilityScore {
  EmployabilityScore(this.items);

  /// In the order a student is nudged to fill them: the cheap, high-signal
  /// items first, evidence that takes longer to earn last.
  factory EmployabilityScore.fromContext(ProfileContext ctx) {
    return EmployabilityScore([
      EmployabilityItem(
        key: 'headline',
        label: 'Headline',
        done: ctx.has('professional_headline'),
        action: 'write a professional headline',
      ),
      EmployabilityItem(
        key: 'education',
        label: 'Education',
        done: ctx.education.isNotEmpty,
        action: 'add your education',
      ),
      EmployabilityItem(
        key: 'skills',
        label: 'Skills',
        done: ctx.skillNames.isNotEmpty,
        action: 'list your skills',
      ),
      EmployabilityItem(
        key: 'cv',
        label: 'CV on file',
        done: ctx.has('cv_path'),
        action: 'upload your CV',
      ),
      EmployabilityItem(
        key: 'work_experience',
        label: 'Work experience',
        done: ctx.workExperience.isNotEmpty,
        action: 'add work experience',
      ),
      EmployabilityItem(
        key: 'projects',
        label: 'Projects',
        done: ctx.projects.isNotEmpty,
        action: 'add a project',
      ),
      EmployabilityItem(
        key: 'links',
        label: 'GitHub, LinkedIn or website',
        done: ctx.has('github_url') || ctx.has('linkedin_url') || ctx.has('website_url'),
        action: 'link your GitHub, LinkedIn or website',
      ),
      EmployabilityItem(
        key: 'certifications',
        label: 'Certifications',
        done: ctx.certifications.isNotEmpty,
        action: 'add a certification',
      ),
      EmployabilityItem(
        key: 'badges',
        label: 'Badges',
        done: ctx.badges.isNotEmpty,
        action: 'add a badge',
      ),
    ]);
  }

  final List<EmployabilityItem> items;

  int get doneCount => items.where((i) => i.done).length;

  /// 0-100, rounded: 9 items give 0, 11, 22, 33, 44, 56, 67, 78, 89, 100.
  int get score => items.isEmpty ? 0 : (doneCount * 100 / items.length).round();

  /// Roughly what one more item is worth, for the hint.
  int get pointsPerItem => items.isEmpty ? 0 : (100 / items.length).round();

  List<EmployabilityItem> get missing => items.where((i) => !i.done).toList();

  /// "What's missing", in the item order above, never more than three named
  /// so the card stays one or two lines.
  String get hint {
    final todo = missing;
    if (todo.isEmpty) return 'Everything employers look for is on your profile.';

    final named = todo.take(3).map((i) => i.action).toList();
    final rest = todo.length - named.length;
    final list = named.length == 1
        ? named.first
        : '${named.sublist(0, named.length - 1).join(', ')} and ${named.last}';
    final more = rest > 0 ? ' ($rest more after that)' : '';
    final each = todo.length == 1 ? 'That adds' : 'Each adds about';
    return 'Next: $list$more. $each $pointsPerItem points.';
  }
}

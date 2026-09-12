// The Employability Score tile promises a 0-100 number and a hint naming
// what would raise it. These pin down the arithmetic (nine equal items),
// the item order the hint follows, and parity with the six criteria
// get_student_completeness() (migration 018) scores.

import 'package:flutter_test/flutter_test.dart';
import 'package:richfield_connect/services/employability_score.dart';
import 'package:richfield_connect/services/profile_context_service.dart';

ProfileContext context({
  String? headline,
  String? github,
  String? linkedin,
  String? website,
  String? cvPath,
  int skills = 0,
  int education = 0,
  int work = 0,
  int projects = 0,
  int certifications = 0,
  int badges = 0,
}) {
  List<Map<String, dynamic>> rows(int n, String key) =>
      [for (var i = 0; i < n; i++) {key: '$key $i'}];
  return ProfileContext(
    profile: {
      'first_name': 'Thabo',
      'role': 'student',
      'professional_headline': headline,
      'github_url': github,
      'linkedin_url': linkedin,
      'website_url': website,
      'cv_path': cvPath,
    },
    skills: rows(skills, 'skill_name'),
    education: rows(education, 'programme'),
    workExperience: rows(work, 'title'),
    projects: rows(projects, 'title'),
    certifications: rows(certifications, 'title'),
    badges: rows(badges, 'title'),
  );
}

void main() {
  test('a brand-new account scores 0 and is pointed at the first three items', () {
    final score = EmployabilityScore.fromContext(context());
    expect(score.items.length, 9);
    expect(score.score, 0);
    expect(score.missing.map((i) => i.key).toList(),
        ['headline', 'education', 'skills', 'cv', 'work_experience', 'projects', 'links', 'certifications', 'badges']);
    expect(score.hint,
        'Next: write a professional headline, add your education and list your skills (6 more after that). Each adds about 11 points.');
  });

  test('a complete profile scores 100 with nothing missing', () {
    final score = EmployabilityScore.fromContext(context(
      headline: 'Junior developer',
      github: 'https://github.com/thabo',
      cvPath: 'uid/cv.pdf',
      skills: 3,
      education: 1,
      work: 1,
      projects: 1,
      certifications: 1,
      badges: 1,
    ));
    expect(score.score, 100);
    expect(score.missing, isEmpty);
    expect(score.hint, 'Everything employers look for is on your profile.');
  });

  test('each item is worth the same and the score is rounded', () {
    // 6 of 9 done -> 66.67 -> 67
    final score = EmployabilityScore.fromContext(context(
      headline: 'x', skills: 1, education: 1, work: 1, projects: 1, certifications: 1,
    ));
    expect(score.doneCount, 6);
    expect(score.score, 67);
    expect(score.pointsPerItem, 11);
    expect(score.hint, 'Next: upload your CV, link your GitHub, LinkedIn or website and add a badge. Each adds about 11 points.');
  });

  test('a single missing item gets a singular hint', () {
    final score = EmployabilityScore.fromContext(context(
      headline: 'x', github: 'g', cvPath: 'c',
      skills: 1, education: 1, work: 1, projects: 1, certifications: 1,
    ));
    expect(score.score, 89);
    expect(score.hint, 'Next: add a badge. That adds 11 points.');
  });

  test('any one public link counts, and blank strings do not', () {
    expect(EmployabilityScore.fromContext(context(linkedin: 'https://linkedin.com/in/t')).missing.map((i) => i.key),
        isNot(contains('links')));
    expect(EmployabilityScore.fromContext(context(website: 'https://t.dev')).missing.map((i) => i.key),
        isNot(contains('links')));
    expect(EmployabilityScore.fromContext(context(github: '   ', headline: '')).missing.map((i) => i.key),
        containsAll(['links', 'headline']));
  });

  test('the six shared criteria match get_student_completeness: any row counts', () {
    // The RPC uses EXISTS per table, so one skill is enough (unlike the
    // Career AI checklist, which asks for three).
    final score = EmployabilityScore.fromContext(context(
      headline: 'x', skills: 1, education: 1, work: 1, projects: 1, certifications: 1,
    ));
    final shared = ['headline', 'education', 'skills', 'work_experience', 'projects', 'certifications'];
    for (final key in shared) {
      expect(score.items.firstWhere((i) => i.key == key).done, isTrue, reason: key);
    }
    // Six of nine done is the RPC's 100% expressed over nine items.
    expect(score.score, 67);
  });
}

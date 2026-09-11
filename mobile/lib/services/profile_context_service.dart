// mobile/lib/services/profile_context_service.dart
//
// Everything the Career AI assistant knows about the signed-in user, loaded
// in one parallel round trip: the profiles row plus the separate skills,
// education, work_experience, projects and certifications tables.
//
// Two jobs:
//   1. steps — which onboarding steps are actually done. Drives the progress
//      bar in the assistant and the Career AI sheet, so "profile strength"
//      is computed from real rows instead of the hardcoded 72% / 'TOP 28%'
//      the sheet used to show.
//   2. toAssistantJson() — the summary sent to the AI service. Deliberately
//      NOT the raw profiles row (see ai_service.dart): only what a model
//      needs to give specific advice goes to a third-party API.

import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileStep {
  const ProfileStep({
    required this.key,
    required this.label,
    required this.done,
    required this.why,
    required this.prompt,
  });

  final String key;
  final String label;
  final bool done;

  /// One line on why it matters, shown under the step.
  final String why;

  /// What the assistant is asked when the user taps this step.
  final String prompt;
}

class ProfileContext {
  ProfileContext({
    required this.profile,
    required this.skills,
    required this.education,
    required this.workExperience,
    required this.projects,
    required this.certifications,
  });

  final Map<String, dynamic> profile;
  final List<Map<String, dynamic>> skills;
  final List<Map<String, dynamic>> education;
  final List<Map<String, dynamic>> workExperience;
  final List<Map<String, dynamic>> projects;
  final List<Map<String, dynamic>> certifications;

  String text(String key) => (profile[key] as String?)?.trim() ?? '';
  bool has(String key) => text(key).isNotEmpty;

  String get firstName => text('first_name');
  String get role => text('role');

  List<String> get skillNames => skills
      .map((s) => (s['skill_name'] as String?)?.trim() ?? '')
      .where((s) => s.isNotEmpty)
      .toList();

  List<ProfileStep> get steps => [
        ProfileStep(
          key: 'headline',
          label: 'Headline',
          done: has('professional_headline'),
          why: 'The first line a recruiter reads about you.',
          prompt: 'Help me write my professional headline.',
        ),
        ProfileStep(
          key: 'skills',
          label: '3+ skills',
          done: skillNames.length >= 3,
          why: 'Skills power job matching and endorsements.',
          prompt: 'Which skills should I add to my profile next?',
        ),
        ProfileStep(
          key: 'education',
          label: 'Education',
          done: education.isNotEmpty,
          why: 'Connects you to your programme and its career pathways.',
          prompt: 'How should I present my education on my profile?',
        ),
        ProfileStep(
          key: 'experience',
          label: 'Experience or project',
          done: workExperience.isNotEmpty || projects.isNotEmpty,
          why: 'Evidence that you can apply what you know.',
          prompt: "I don't have much work experience yet. What projects could I add?",
        ),
        ProfileStep(
          key: 'bio',
          label: 'About you',
          done: has('bio'),
          why: 'A short summary in your own voice.',
          prompt: 'Help me write a short About section for my profile.',
        ),
        ProfileStep(
          key: 'links',
          label: 'GitHub or LinkedIn',
          done: has('github_url') || has('linkedin_url') || has('website_url'),
          why: 'Lets recruiters check your work for themselves.',
          prompt: 'What should I have on my GitHub or LinkedIn before I link it?',
        ),
        ProfileStep(
          key: 'photo',
          label: 'Profile photo',
          done: has('avatar_path'),
          why: 'Makes you recognisable across the network.',
          prompt: 'What makes a good professional profile photo?',
        ),
      ];

  int get doneCount => steps.where((s) => s.done).length;
  double get completeness => doneCount / steps.length;

  ProfileStep? get nextStep {
    for (final step in steps) {
      if (!step.done) return step;
    }
    return null;
  }

  Map<String, dynamic> toAssistantJson() {
    final allSteps = steps;
    return {
      'first_name': firstName,
      'last_name': text('last_name'),
      'role': role,
      'professional_headline': text('professional_headline'),
      'career_interests': text('career_interests'),
      'bio': text('bio'),
      'has_profile_photo': has('avatar_path'),
      'links': {
        'github': has('github_url'),
        'linkedin': has('linkedin_url'),
        'website': has('website_url'),
      },
      'skills': skillNames,
      'education': [
        for (final e in education)
          {
            'programme': e['programme'],
            'campus': e['campus'],
            'enrolment_year': e['enrolment_year'],
            'graduation_year': e['graduation_year'],
          },
      ],
      'work_experience': [
        for (final w in workExperience)
          {'title': w['title'], 'organisation': w['organisation'], 'description': w['description']},
      ],
      'projects': [
        for (final p in projects) {'title': p['title'], 'description': p['description']},
      ],
      'certifications': [
        for (final c in certifications) {'title': c['title'], 'issuer': c['issuer']},
      ],
      'completed_sections': [for (final s in allSteps) if (s.done) s.key],
      'missing_sections': [for (final s in allSteps) if (!s.done) s.key],
    };
  }
}

class ProfileContextService {
  ProfileContextService(this._client);

  final SupabaseClient _client;

  Future<ProfileContext> load(String userId) async {
    final results = await Future.wait<dynamic>([
      _client
          .from('profiles')
          .select('first_name, last_name, role, professional_headline, career_interests, '
              'bio, avatar_path, github_url, linkedin_url, website_url')
          .eq('id', userId)
          .single(),
      _client.from('skills').select('id, skill_name').eq('profile_id', userId).order('created_at'),
      _client
          .from('education')
          .select('programme, campus, enrolment_year, graduation_year')
          .eq('profile_id', userId)
          .order('enrolment_year', ascending: false),
      _client
          .from('work_experience')
          .select('title, organisation, description')
          .eq('profile_id', userId),
      _client.from('projects').select('title, description').eq('profile_id', userId),
      _client.from('certifications').select('title, issuer').eq('profile_id', userId),
    ]);

    List<Map<String, dynamic>> rows(int i) => List<Map<String, dynamic>>.from(results[i] as List);

    return ProfileContext(
      profile: Map<String, dynamic>.from(results[0] as Map),
      skills: rows(1),
      education: rows(2),
      workExperience: rows(3),
      projects: rows(4),
      certifications: rows(5),
    );
  }
}

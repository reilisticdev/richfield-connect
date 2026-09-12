// mobile/lib/widgets/ai_consent_prompt.dart
//
// Nothing reaches the AI service until the member agrees. The AI screens call
// ensureAiConsent() before each request; the answer is stored in
// consent_records ('ai_processing') and can be withdrawn from Privacy & data.

import 'package:flutter/material.dart';

import '../services/auth_error_mapper.dart';
import '../services/privacy_service.dart';

const aiProcessingExplanation =
    'The assistant sends your profile summary (such as your name, headline, bio, career interests, '
    'skills, education, experience and projects) and whatever you type, paste or upload, such as a CV, '
    'through Richfield Connect\'s AI server to Google\'s Gemini service. Google may process it '
    'outside South Africa.';

Future<bool> ensureAiConsent(BuildContext context, {PrivacyService? service}) async {
  final privacy = service ?? PrivacyService();
  try {
    if (await privacy.hasAiConsent()) return true;
  } catch (_) {
    // If the check itself fails, ask anyway; a failed grant is reported below.
  }
  if (!context.mounted) return false;

  final allow = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Allow the Career AI assistant?'),
      content: const SingleChildScrollView(
        child: Text(
          '$aiProcessingExplanation\n\nNothing is sent until you allow it. You can withdraw this at any '
          'time from Privacy & data in the account menu.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Allow')),
      ],
    ),
  );
  if (allow != true) return false;

  try {
    await privacy.grant(ConsentType.aiProcessing);
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthErrorMapper.fromAny(e))));
    }
    return false;
  }
}

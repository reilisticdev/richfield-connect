// mobile/lib/screens/ai_assistant_screen.dart
//
// Richfield Career AI — the profile assistant for rubric section 6.
//
// Replaces AiProfileInputScreen, which was one text box that sent one
// message and showed one reply: no conversation, no memory of the previous
// answer, and nothing that walked a new user through setup.
//
// What makes this an onboarding assistant rather than a generic chatbot:
//   * the transcript is replayed to /api/chat every turn, so follow-ups work;
//   * the user's real profile (ProfileContext) rides along, so advice is
//     about their actual gaps;
//   * guided mode has the service take ONE missing section per reply, and
//     the step chips along the top track progress against the database;
//   * advice can be applied, not just read — "Suggest skills" returns
//     structured JSON and chosen skills are inserted into `skills`, and
//     "Import my CV" runs the NLP parser (cv_import_screen.dart).
// It stays available after onboarding from the Portfolio sparkle button and
// the account menu.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/ai_config.dart';
import '../main.dart' show AppColors, AppRadius, AppSpace, AppText;
import '../services/ai_service.dart';
import '../services/auth_error_mapper.dart';
import '../services/profile_context_service.dart';
import '../services/profile_service.dart';
import 'cv_import_screen.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key, this.guided = false, this.initialMessage});

  /// First-time setup: the service works through missing sections in order.
  final bool guided;

  /// Sent as the user's first message once the profile has loaded — used by
  /// the Career AI sheet's question chips.
  final String? initialMessage;

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

enum _Kind { user, assistant, note, error, skills }

class _Msg {
  _Msg(this.kind, this.text, {this.hidden = false, this.suggestions, this.retry});

  final _Kind kind;
  final String text;

  /// Part of the transcript sent to the service, but not drawn. Used for the
  /// guided-mode kickoff, which would read oddly as a bubble.
  final bool hidden;

  final SkillSuggestions? suggestions;
  final VoidCallback? retry;

  /// Only real user/assistant turns are replayed. Notes (local status lines)
  /// and error cards never reach the model.
  bool get isTranscript => kind == _Kind.user || kind == _Kind.assistant;
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final _client = Supabase.instance.client;
  late final _contextService = ProfileContextService(_client);
  late final _profileService = ProfileService(_client);
  final _ai = AiService();
  final _input = TextEditingController();
  final _scroll = ScrollController();

  final List<_Msg> _messages = [];
  ProfileContext? _ctx;
  String? _loadError;
  bool _busy = false;

  /// Chip selection per suggestions card, and which cards were already applied.
  final Map<_Msg, Set<String>> _picked = {};
  final Set<_Msg> _applied = {};

  String? get _userId => _client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final loaded = await _reloadContext();
    if (!loaded || !mounted) return;

    final initial = widget.initialMessage?.trim() ?? '';
    if (widget.guided) {
      await _send('Start my profile setup.', hidden: true);
    } else if (initial.isNotEmpty) {
      await _send(initial);
    } else {
      final name = _ctx!.firstName;
      _add(_Msg(
        _Kind.note,
        'Hi${name.isEmpty ? '' : ' $name'}! I can review your profile, suggest skills, '
        'draft a headline, or pull details out of your CV. What would you like to work on?',
      ));
    }
  }

  Future<bool> _reloadContext() async {
    final userId = _userId;
    if (userId == null) {
      setState(() => _loadError = 'Your session has expired. Sign in again.');
      return false;
    }
    try {
      final ctx = await _contextService.load(userId);
      if (!mounted) return false;
      setState(() {
        _ctx = ctx;
        _loadError = null;
      });
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _loadError = AuthErrorMapper.fromAny(e));
      return false;
    }
  }

  void _add(_Msg message) {
    setState(() => _messages.add(message));
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  String _describe(Object e) => e is AiServiceException ? e.message : AuthErrorMapper.fromAny(e);

  Future<void> _send(String text, {bool hidden = false}) async {
    final message = text.trim();
    final ctx = _ctx;
    if (message.isEmpty || _busy || ctx == null) return;

    // The transcript BEFORE this message; the service appends `message`
    // itself as the newest user turn.
    final history = [
      for (final m in _messages)
        if (m.isTranscript) AiChatTurn(fromUser: m.kind == _Kind.user, text: m.text),
    ];

    final userMessage = _Msg(_Kind.user, message, hidden: hidden);
    setState(() {
      _messages.removeWhere((m) => m.kind == _Kind.error);
      _messages.add(userMessage);
      _busy = true;
    });
    _scrollToEnd();

    try {
      final reply = await _ai.chat(
        message: message,
        profile: ctx.toAssistantJson(),
        history: history,
        onboarding: widget.guided,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      _add(_Msg(_Kind.assistant, reply));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // Drop the unanswered turn so a retry doesn't send it twice.
        _messages.remove(userMessage);
      });
      _add(_Msg(_Kind.error, _describe(e), retry: () => _send(message, hidden: hidden)));
    }
  }

  Future<void> _suggestSkills() async {
    final ctx = _ctx;
    if (ctx == null || _busy) return;
    setState(() {
      _messages.removeWhere((m) => m.kind == _Kind.error);
      _busy = true;
    });
    _scrollToEnd();

    try {
      final result = await _ai.suggestSkills(profile: ctx.toAssistantJson());
      if (!mounted) return;
      final card = _Msg(_Kind.skills, result.reason, suggestions: result);
      setState(() {
        _busy = false;
        _picked[card] = result.skills.toSet();
      });
      _add(card);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _add(_Msg(_Kind.error, _describe(e), retry: _suggestSkills));
    }
  }

  Future<void> _applySkills(_Msg card) async {
    final userId = _userId;
    final chosen = _picked[card] ?? <String>{};
    if (userId == null || chosen.isEmpty || _busy) return;

    setState(() => _busy = true);
    try {
      final added = await _profileService.addSkills(userId: userId, names: chosen);
      await _reloadContext();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _applied.add(card);
      });
      _add(_Msg(
        _Kind.note,
        added.isEmpty
            ? 'You already had all of those on your profile.'
            : 'Added ${added.join(', ')} to your profile. '
                'You now list ${_ctx?.skillNames.length ?? added.length} skills.',
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _add(_Msg(_Kind.error, _describe(e)));
    }
  }

  Future<void> _openCvImport() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CvImportScreen()),
    );
    if (changed != true || !mounted) return;

    await _reloadContext();
    final ctx = _ctx;
    if (!mounted || ctx == null) return;
    _add(_Msg(
      _Kind.note,
      'Profile updated from your CV — ${ctx.doneCount} of ${ctx.steps.length} setup steps done.',
    ));
    if (widget.guided && ctx.nextStep != null) {
      await _send('I just imported my CV into my profile. What should I work on next?');
    }
  }

  Future<void> _changeServer() async {
    final saved = await showDialog<bool>(context: context, builder: (_) => const _ServerDialog());
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI server address saved.')),
      );
    }
  }

  void _submitInput() {
    final text = _input.text;
    if (text.trim().isEmpty || _busy) return;
    _input.clear();
    _send(text);
  }

  @override
  Widget build(BuildContext context) {
    final ctx = _ctx;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(Icons.auto_awesome, size: 18, color: AppColors.onPrimary),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Career AI', style: AppText.headlineSm()),
                  Text(
                    widget.guided ? 'Guided profile setup' : 'Your profile assistant',
                    style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Import from CV',
            onPressed: _busy || ctx == null ? null : _openCvImport,
            icon: const Icon(Icons.description_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'server') _changeServer();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'server', child: Text('AI server address')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (ctx != null) _progressHeader(ctx),
            Expanded(child: _conversation()),
            if (ctx != null) _quickActions(ctx),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _progressHeader(ProfileContext ctx) {
    final steps = ctx.steps;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.base, AppSpace.sm, AppSpace.base, AppSpace.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Profile setup', style: AppText.labelLg()),
              const Spacer(),
              Text(
                '${ctx.doneCount} of ${steps.length} done',
                style: AppText.labelMd(color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              value: ctx.completeness,
              minHeight: 6,
              color: AppColors.primary,
              backgroundColor: AppColors.surfaceContainerHigh,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: steps.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final step = steps[i];
                return ActionChip(
                  avatar: Icon(
                    step.done ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 16,
                    color: step.done ? AppColors.successGreen : AppColors.onSurfaceVariant,
                  ),
                  label: Text(
                    step.label,
                    style: AppText.labelMd(
                      color: step.done ? AppColors.onSurfaceVariant : AppColors.onSurface,
                    ),
                  ),
                  tooltip: step.why,
                  onPressed: _busy ? null : () => _send(step.prompt),
                  backgroundColor: AppColors.surfaceContainerLow,
                  side: BorderSide(color: AppColors.outlineVariant),
                  visualDensity: VisualDensity.compact,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _conversation() {
    final error = _loadError;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: AppColors.error),
              const SizedBox(height: AppSpace.sm),
              Text(error, textAlign: TextAlign.center, style: AppText.bodyMd()),
              const SizedBox(height: AppSpace.md),
              OutlinedButton(onPressed: _start, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_ctx == null) return const Center(child: CircularProgressIndicator());

    final visible = _messages.where((m) => !m.hidden).toList();
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(AppSpace.base),
      itemCount: visible.length + (_busy ? 1 : 0),
      itemBuilder: (_, i) => i == visible.length ? _thinkingBubble() : _bubble(visible[i]),
    );
  }

  Widget _bubble(_Msg m) {
    switch (m.kind) {
      case _Kind.user:
        return _aligned(
          fromUser: true,
          color: AppColors.primary,
          child: Text(m.text, style: AppText.bodyMd(color: AppColors.onPrimary)),
        );
      case _Kind.assistant:
        return _aligned(
          fromUser: false,
          color: AppColors.surfaceContainerLowest,
          bordered: true,
          child: SelectableText.rich(formatAssistantReply(m.text, AppText.bodyMd())),
        );
      case _Kind.note:
        return _aligned(
          fromUser: false,
          color: AppColors.surfaceContainerLow,
          child: Text(m.text, style: AppText.bodyMd(color: AppColors.onSurfaceVariant)),
        );
      case _Kind.error:
        return _errorCard(m);
      case _Kind.skills:
        return _skillsCard(m);
    }
  }

  Widget _aligned({
    required bool fromUser,
    required Color color,
    required Widget child,
    bool bordered = false,
  }) {
    const big = Radius.circular(AppRadius.xl);
    const small = Radius.circular(AppRadius.sm);
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpace.sm),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
        decoration: BoxDecoration(
          color: color,
          border: bordered ? Border.all(color: AppColors.outlineVariant) : null,
          borderRadius: BorderRadius.only(
            topLeft: big,
            topRight: big,
            bottomLeft: fromUser ? big : small,
            bottomRight: fromUser ? small : big,
          ),
        ),
        child: child,
      ),
    );
  }

  Widget _thinkingBubble() {
    return _aligned(
      fromUser: false,
      color: AppColors.surfaceContainerLow,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
          ),
          const SizedBox(width: AppSpace.sm),
          Text('Thinking…', style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _errorCard(_Msg m) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.cloud_off_outlined, size: 18, color: AppColors.onErrorContainer),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(m.text, style: AppText.bodySm(color: AppColors.onErrorContainer)),
              ),
            ],
          ),
          Wrap(
            spacing: AppSpace.sm,
            children: [
              if (m.retry != null)
                TextButton(onPressed: _busy ? null : m.retry, child: const Text('Retry')),
              TextButton(onPressed: _changeServer, child: const Text('AI server address')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _skillsCard(_Msg card) {
    final suggestions = card.suggestions!;
    final picked = _picked[card] ?? <String>{};
    final applied = _applied.contains(card);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 18, color: AppColors.tertiary),
              const SizedBox(width: 6),
              Text('Skills that fit your profile', style: AppText.labelLg()),
            ],
          ),
          if (suggestions.reason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(suggestions.reason, style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
          ],
          const SizedBox(height: AppSpace.sm),
          if (suggestions.skills.isEmpty)
            Text(
              'Nothing new to suggest — your skills already cover the essentials.',
              style: AppText.bodySm(),
            )
          else ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final skill in suggestions.skills)
                  FilterChip(
                    label: Text(skill),
                    selected: picked.contains(skill),
                    onSelected: applied
                        ? null
                        : (on) => setState(() {
                              if (on) {
                                picked.add(skill);
                              } else {
                                picked.remove(skill);
                              }
                            }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: applied || picked.isEmpty || _busy ? null : () => _applySkills(card),
                icon: Icon(applied ? Icons.check : Icons.add, size: 18),
                label: Text(applied ? 'Added' : 'Add ${picked.length} to my profile'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _quickActions(ProfileContext ctx) {
    final next = ctx.nextStep;
    final actions = <(String, IconData, VoidCallback)>[
      ('Suggest skills', Icons.lightbulb_outline, _suggestSkills),
      ('Import my CV', Icons.description_outlined, _openCvImport),
      if (next != null) ('Help with: ${next.label}', Icons.flag_outlined, () => _send(next.prompt)),
      (
        'What next?',
        Icons.explore_outlined,
        () => _send('Looking at my profile, what is the single most useful thing I should do next?'),
      ),
    ];

    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.base, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final (label, icon, onTap) = actions[i];
          return ActionChip(
            avatar: Icon(icon, size: 16, color: AppColors.primary),
            label: Text(label, style: AppText.labelMd()),
            onPressed: _busy ? null : onTap,
            backgroundColor: AppColors.surfaceContainerLowest,
            side: BorderSide(color: AppColors.outlineVariant),
          );
        },
      ),
    );
  }

  Widget _composer() {
    final ready = _ctx != null && !_busy;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.base, AppSpace.xs, AppSpace.sm, AppSpace.sm),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              enabled: _ctx != null,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submitInput(),
              decoration: InputDecoration(
                hintText: 'Ask about your profile or career…',
                filled: true,
                fillColor: AppColors.surfaceContainerLow,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: ready ? _submitInput : null,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

/// Gemini replies in light Markdown — **bold**, "- " / "* " bullets and the
/// occasional "## heading" — and there's no markdown package in pubspec.
/// Raw asterisks read as noise, so render just those constructs and leave
/// everything else as plain text.
TextSpan formatAssistantReply(String text, TextStyle base) {
  final bold = base.copyWith(fontWeight: FontWeight.w700);
  final bulletPattern = RegExp(r'^\s*[*\-]\s+');
  final headingPattern = RegExp(r'^\s*#{1,6}\s+');
  final lines = text.trimRight().split('\n');
  final spans = <InlineSpan>[];

  for (var li = 0; li < lines.length; li++) {
    var line = lines[li];
    var wholeLineBold = false;

    final heading = headingPattern.firstMatch(line);
    if (heading != null) {
      line = line.substring(heading.end);
      wholeLineBold = true;
    }
    final bullet = bulletPattern.firstMatch(line);
    if (bullet != null) line = '•  ${line.substring(bullet.end)}';

    final parts = line.split('**');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      spans.add(TextSpan(text: parts[i], style: wholeLineBold || i.isOdd ? bold : base));
    }
    if (li < lines.length - 1) spans.add(const TextSpan(text: '\n'));
  }
  return TextSpan(style: base, children: spans);
}

class _ServerDialog extends StatefulWidget {
  const _ServerDialog();

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  late final _controller = TextEditingController(
    text: AiConfig.isConfigured ? AiConfig.baseUrl : '',
  );
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save({bool skipCheck = false}) async {
    final url = AiConfig.normalize(_controller.text);
    if (url == null) {
      setState(() => _error = 'Enter the server address, e.g. https://example.ngrok-free.app');
      return;
    }
    if (!skipCheck) {
      setState(() {
        _checking = true;
        _error = null;
      });
      final healthy = await AiService.isHealthy(url);
      if (!mounted) return;
      if (!healthy) {
        setState(() {
          _checking = false;
          _error = 'No AI service answered at that address.';
        });
        return;
      }
    }
    await AiConfig.setOverride(url);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _reset() async {
    await AiConfig.setOverride(null);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('AI server address'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The assistant runs on a separate service. If its tunnel restarted, paste the new address here.',
            style: AppText.bodySm(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText: 'https://….ngrok-free.app',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(_error!, style: AppText.bodySm(color: AppColors.error)),
          ],
        ],
      ),
      actions: [
        if (AiConfig.hasDeviceOverride && !_checking)
          TextButton(onPressed: _reset, child: const Text('Reset')),
        if (_error != null && !_checking)
          TextButton(onPressed: () => _save(skipCheck: true), child: const Text('Save anyway')),
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _checking ? null : _save,
          child: Text(_checking ? 'Checking…' : 'Check & save'),
        ),
      ],
    );
  }
}

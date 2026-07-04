import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/ai_service.dart';

/// Composer AI tools: rewrite the draft in a tone, fix grammar, translate,
/// or compose something new from a prompt/template. Returns the text the
/// user chose to put into the composer, or null.
Future<String?> showAiAssistantSheet(
  BuildContext context, {
  required String draft,
  required List<AiMessage> Function() contextBuilder,
  required String translateLanguage,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _AiAssistantSheet(
        draft: draft,
        contextBuilder: contextBuilder,
        translateLanguage: translateLanguage,
      ),
    ),
  );
}

class _AiAssistantSheet extends StatefulWidget {
  final String draft;
  final List<AiMessage> Function() contextBuilder;
  final String translateLanguage;

  const _AiAssistantSheet({
    required this.draft,
    required this.contextBuilder,
    required this.translateLanguage,
  });

  @override
  State<_AiAssistantSheet> createState() => _AiAssistantSheetState();
}

class _AiAssistantSheetState extends State<_AiAssistantSheet> {
  final _promptController = TextEditingController();
  bool _loading = false;
  String? _result;
  String? _error;
  String _loadingLabel = '';

  static const _templates = <String, String>{
    '🙏 Apology': 'Write a sincere, short apology message',
    '🎂 Birthday': 'Write a warm birthday wish',
    '🎉 Congratulations': 'Write a congratulations message',
    '🕯️ Condolence': 'Write a gentle condolence message',
    '📅 Meeting reply': 'Write a reply confirming the meeting time works',
    '🤝 Follow-up': 'Write a polite follow-up on my last message',
    '💼 Business email': 'Write a short professional business message',
    '💰 Negotiation': 'Write a firm but friendly negotiation reply',
    '🎧 Support reply': 'Write a helpful customer support response',
    '📣 Social caption': 'Write a catchy social media caption with hashtags',
  };

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  bool get _hasDraft => widget.draft.trim().isNotEmpty;

  Future<void> _run(String label, Future<AiResult> future) async {
    setState(() {
      _loading = true;
      _loadingLabel = label;
      _result = null;
      _error = null;
    });
    final res = await future;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = res.text;
      _error = res.ok ? null : res.error;
      if (res.ok && (res.text == null || res.text!.trim().isEmpty)) {
        _error = 'The assistant returned an empty result.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [c.accent, c.bubbleMineDeep]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Text('Allora AI',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: c.text)),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading) ...[
              _LoadingCard(label: _loadingLabel),
            ] else if (_result != null) ...[
              _ResultCard(
                text: _result!,
                onUse: () => Navigator.pop(context, _result),
                onCopy: () {
                  Clipboard.setData(ClipboardData(text: _result!));
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied')));
                },
                onRetry: () => setState(() => _result = null),
              ),
            ] else ...[
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_error!,
                      style: TextStyle(fontSize: 13, color: c.danger)),
                ),
              if (_hasDraft) ...[
                Text('REWRITE YOUR DRAFT',
                    style: _sectionStyle(c)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tone in AiTone.values)
                      ActionChip(
                        avatar: Text(tone.emoji,
                            style: const TextStyle(fontSize: 14)),
                        label: Text(tone.label),
                        onPressed: () => _run('Rewriting (${tone.label})…',
                            AiService.rewrite(widget.draft, tone)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _run('Fixing grammar…',
                            AiService.fixGrammar(widget.draft)),
                        icon: const Icon(Icons.spellcheck_rounded, size: 17),
                        label: const Text('Fix grammar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _run(
                            'Translating…',
                            AiService.translate(
                                widget.draft, widget.translateLanguage)),
                        icon: const Icon(Icons.translate_rounded, size: 17),
                        label: Text('→ ${widget.translateLanguage}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              Text('COMPOSE SOMETHING NEW', style: _sectionStyle(c)),
              const SizedBox(height: 8),
              TextField(
                controller: _promptController,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Describe what to write…',
                  suffixIcon: IconButton(
                    icon: Icon(Icons.arrow_forward_rounded, color: c.accent),
                    onPressed: () {
                      final p = _promptController.text.trim();
                      if (p.isEmpty) return;
                      _run('Composing…', AiService.compose(p));
                    },
                  ),
                ),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) {
                    _run('Composing…', AiService.compose(v.trim()));
                  }
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in _templates.entries)
                    ActionChip(
                      label: Text(t.key, style: const TextStyle(fontSize: 12.5)),
                      onPressed: () =>
                          _run('Composing…', AiService.compose(t.value)),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => _run(
                    'Reading the conversation…',
                    AiService.generateReply(widget.contextBuilder(),
                        'Suggest the best reply to the conversation')),
                icon: const Icon(Icons.reply_all_rounded, size: 17),
                label: const Text('Suggest a reply from context'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  TextStyle _sectionStyle(AlloraColors c) => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: c.textTertiary,
      );
}

class _LoadingCard extends StatelessWidget {
  final String label;
  const _LoadingCard({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    return Container(
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Column(
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.6, color: c.accent),
          ),
          const SizedBox(height: 14),
          Text(label,
              style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String text;
  final VoidCallback onUse;
  final VoidCallback onCopy;
  final VoidCallback onRetry;

  const _ResultCard({
    required this.text,
    required this.onUse,
    required this.onCopy,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          constraints: const BoxConstraints(maxHeight: 260),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.outline),
          ),
          child: SingleChildScrollView(
            child: SelectableText(text,
                style: TextStyle(fontSize: 15, height: 1.45, color: c.text)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              tooltip: 'Try again',
              onPressed: onRetry,
              icon: Icon(Icons.refresh_rounded, color: c.textSecondary),
            ),
            IconButton(
              tooltip: 'Copy',
              onPressed: onCopy,
              icon: Icon(Icons.copy_rounded, color: c.textSecondary),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: onUse,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Use this'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Generic "AI result" sheet used by message actions (Translate, Explain,
/// Summarize, Extract tasks). Shows a loader, then the result with copy.
void showAiResultSheet(
  BuildContext context, {
  required String title,
  required IconData icon,
  required Future<AiResult> future,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final c = ctx.allora;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: FutureBuilder<AiResult>(
            future: future,
            builder: (context, snap) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 20, color: c.accent),
                      const SizedBox(width: 10),
                      Text(title,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: c.text)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (!snap.hasData)
                    const Padding(
                      padding: EdgeInsets.all(28),
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2.6)),
                    )
                  else if (!snap.data!.ok)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: c.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(snap.data!.error ?? 'Something went wrong.',
                          style: TextStyle(fontSize: 13.5, color: c.danger)),
                    )
                  else ...[
                    Container(
                      constraints: BoxConstraints(
                          maxHeight:
                              MediaQuery.of(context).size.height * 0.5),
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: c.surfaceAlt,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          snap.data!.text ?? '',
                          style: TextStyle(
                              fontSize: 15, height: 1.5, color: c.text),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: snap.data!.text ?? ''));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Copied')));
                        },
                        icon: const Icon(Icons.copy_rounded, size: 17),
                        label: const Text('Copy'),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

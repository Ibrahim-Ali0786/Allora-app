import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/ai_service.dart';
import '../../data/settings/app_settings.dart';

/// The "Allora AI" assistant conversation. Runs entirely against the
/// server-side AI function; history is stored on-device only (and not at
/// all in incognito / when AI history is off).
class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, String>> _history = [];
  bool _thinking = false;
  bool _loaded = false;

  static const _suggestions = [
    'Write a professional follow-up message',
    'Translate "see you tomorrow" to Spanish',
    'Draft a birthday wish for a close friend',
    'Fix the grammar: "me and him goes shop yesterday"',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (ref.read(settingsProvider).effectiveAiHistory) {
      _history = await AiChatStore.load();
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ask(String prompt) async {
    final text = prompt.trim();
    if (text.isEmpty || _thinking) return;
    _controller.clear();
    HapticFeedback.lightImpact();
    setState(() {
      _history = [..._history, {'role': 'user', 'text': text}];
      _thinking = true;
    });
    _scrollToEnd();

    final res = await AiService.chat(_history.length > 24
        ? _history.sublist(_history.length - 24)
        : _history);
    if (!mounted) return;

    setState(() {
      _thinking = false;
      _history = [
        ..._history,
        {
          'role': 'assistant',
          'text': res.ok
              ? (res.text ?? '…')
              : (res.error ?? 'Something went wrong.'),
        },
      ];
    });
    _scrollToEnd();
    if (ref.read(settingsProvider).effectiveAiHistory) {
      await AiChatStore.save(_history);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent + 80,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    final historyOn =
        ref.watch(settingsProvider.select((s) => s.effectiveAiHistory));

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient:
                    LinearGradient(colors: [c.accent, c.bubbleMineDeep]),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Allora AI',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: c.text)),
                Text(historyOn ? 'History on device' : 'History off',
                    style:
                        TextStyle(fontSize: 11.5, color: c.textSecondary)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Clear conversation',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              await AiChatStore.clear();
              setState(() => _history = []);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
                : _history.isEmpty
                    ? _welcome()
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        itemCount: _history.length + (_thinking ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i >= _history.length) return _thinkingBubble();
                          final m = _history[i];
                          final isUser = m['role'] == 'user';
                          return _bubble(m['text'] ?? '', isUser);
                        },
                      ),
          ),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _welcome() {
    final c = context.allora;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 30),
        Center(
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [c.accent, c.bubbleMineDeep]),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: c.accent.withValues(alpha: 0.35),
                    blurRadius: 30,
                    offset: const Offset(0, 10)),
              ],
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 34),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text('How can I help?',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: c.text)),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Compose, rewrite, translate, summarize —\nyour messaging copilot.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13.5, color: c.textSecondary, height: 1.5),
          ),
        ),
        const SizedBox(height: 26),
        for (final s in _suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _ask(s),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.outline),
                ),
                child: Row(
                  children: [
                    Icon(Icons.chat_bubble_outline_rounded,
                        size: 16, color: c.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(s,
                          style: TextStyle(fontSize: 13.5, color: c.text)),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _bubble(String text, bool isUser) {
    final c = context.allora;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: text));
          HapticFeedback.mediumImpact();
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Copied')));
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
          decoration: BoxDecoration(
            color: isUser ? null : c.surface,
            gradient: isUser
                ? LinearGradient(colors: [c.bubbleMine, c.bubbleMineDeep])
                : null,
            borderRadius: BorderRadius.circular(18).copyWith(
              bottomRight: isUser ? const Radius.circular(6) : null,
              bottomLeft: isUser ? null : const Radius.circular(6),
            ),
            border: isUser ? null : Border.all(color: c.outline),
          ),
          child: SelectableText(
            text,
            style: TextStyle(
              fontSize: 15,
              height: 1.45,
              color: isUser ? c.onAccent : c.text,
            ),
          ),
        ),
      ),
    );
  }

  Widget _thinkingBubble() {
    final c = context.allora;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: c.accent),
            ),
            const SizedBox(width: 10),
            Text('Thinking…',
                style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _inputBar() {
    final c = context.allora;
    return Container(
      color: c.surface,
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: 8 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Ask Allora AI…'),
              onSubmitted: _ask,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            style: IconButton.styleFrom(
                backgroundColor: c.accent, minimumSize: const Size(44, 44)),
            onPressed: _thinking ? null : () => _ask(_controller.text),
            icon: const Icon(Icons.arrow_upward_rounded,
                color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }
}

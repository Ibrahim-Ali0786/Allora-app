import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/ai_service.dart';
import '../../data/settings/app_settings.dart';

const kTranslateLanguages = [
  'English', 'Spanish', 'French', 'German', 'Italian', 'Portuguese',
  'Hindi', 'Urdu', 'Arabic', 'Turkish', 'Russian', 'Chinese', 'Japanese',
  'Korean', 'Indonesian', 'Bengali',
];

class AiSettingsScreen extends ConsumerWidget {
  const AiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.allora;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(title: const Text('AI Assistant')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [c.accent, c.bubbleMineDeep],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    color: Colors.white, size: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Allora AI',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      SizedBox(height: 3),
                      Text(
                        'Compose · rewrite · translate · summarize · smart replies',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 12.5, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _card(context, [
            SwitchListTile(
              secondary: Icon(Icons.auto_awesome_rounded, color: c.accent),
              title: const Text('Enable Allora AI'),
              subtitle: const Text('The ✨ button in chats and the assistant'),
              value: settings.aiEnabled,
              onChanged: notifier.setAiEnabled,
            ),
            Divider(color: c.outline, height: 1),
            SwitchListTile(
              secondary: Icon(Icons.reply_all_rounded, color: c.textSecondary),
              title: const Text('Smart replies'),
              subtitle:
                  const Text('One-tap reply suggestions under conversations'),
              value: settings.aiSmartReplies && settings.aiEnabled,
              onChanged:
                  settings.aiEnabled ? notifier.setAiSmartReplies : null,
            ),
            Divider(color: c.outline, height: 1),
            ListTile(
              leading: Icon(Icons.translate_rounded, color: c.textSecondary),
              title: const Text('Translate to'),
              subtitle: Text(settings.aiTranslateLanguage),
              trailing: Icon(Icons.chevron_right_rounded, color: c.textTertiary),
              onTap: () => _pickLanguage(context, ref),
            ),
          ]),
          const SizedBox(height: 14),
          _card(context, [
            ListTile(
              leading:
                  Icon(Icons.delete_sweep_outlined, color: c.textSecondary),
              title: const Text('Clear AI history'),
              subtitle: const Text('Delete the on-device assistant conversation'),
              onTap: () async {
                await AiChatStore.clear();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('AI history cleared')));
                }
              },
            ),
          ]),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Privacy: AI requests run through Allora\u2019s secure backend — '
              'no AI keys live in the app. Only the message you act on (plus, '
              'for context features, the last few messages with names '
              'shortened) is sent, never your full history. Nothing is used '
              'to train models. In Incognito mode the assistant keeps no '
              'history at all.',
              style:
                  TextStyle(fontSize: 12.5, color: c.textTertiary, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, List<Widget> children) {
    final c = context.allora;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  void _pickLanguage(BuildContext context, WidgetRef ref) {
    final current = ref.read(settingsProvider).aiTranslateLanguage;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.6,
        child: ListView(
          children: [
            for (final lang in kTranslateLanguages)
              RadioListTile<String>(
                value: lang,
                groupValue: current,
                title: Text(lang),
                onChanged: (v) {
                  Navigator.pop(ctx);
                  if (v != null) {
                    ref
                        .read(settingsProvider.notifier)
                        .setAiTranslateLanguage(v);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/settings/app_settings.dart';

/// Experimental features. Toggles that map to a real setting are wired to it;
/// the rest are clearly marked as previews so nothing pretends to work when
/// it doesn't.
class LabsSettingsScreen extends ConsumerWidget {
  const LabsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.allora;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(title: const Text('Labs')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: c.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.science_rounded, color: c.warning),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Experimental features. Behaviour may change and some are '
                    'previews only.',
                    style: TextStyle(
                        fontSize: 12.5, color: c.textSecondary, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          _card(context, [
            _lab(
              context,
              icon: Icons.auto_awesome_rounded,
              title: 'AI Smart Reply',
              subtitle: 'One-tap reply suggestions under conversations',
              value: settings.aiSmartReplies && settings.aiEnabled,
              onChanged:
                  settings.aiEnabled ? notifier.setAiSmartReplies : null,
              beta: true,
            ),
            _divider(c),
            _lab(
              context,
              icon: Icons.summarize_rounded,
              title: 'AI Summaries',
              subtitle: 'Summarize long chats from the chat menu',
              value: settings.aiEnabled,
              onChanged: notifier.setAiEnabled,
              beta: true,
            ),
          ]),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Text('COMING SOON', style: _sectionStyle(c)),
          ),
          _card(context, [
            _preview(context, Icons.bubble_chart_rounded, 'Floating chat bubbles',
                'Chat heads that stay on top of other apps'),
            _divider(c),
            _preview(context, Icons.translate_rounded, 'Auto translation',
                'Translate incoming messages automatically'),
            _divider(c),
            _preview(context, Icons.desktop_windows_rounded, 'Desktop sync',
                'Continue conversations on desktop'),
            _divider(c),
            _preview(context, Icons.folder_special_rounded, 'Smart folders',
                'Auto-organise chats by rules'),
            _divider(c),
            _preview(context, Icons.record_voice_over_rounded, 'Voice AI',
                'Hands-free replies and transcription'),
          ]),
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

  Widget _divider(AlloraColors c) =>
      Divider(color: c.outline, height: 1, indent: 60);

  Widget _lab(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    bool beta = false,
  }) {
    final c = context.allora;
    return SwitchListTile(
      secondary: Icon(icon, color: c.accent),
      title: Row(
        children: [
          Flexible(child: Text(title)),
          if (beta) ...[
            const SizedBox(width: 8),
            _badge(c, 'BETA', c.accent),
          ],
        ],
      ),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _preview(
      BuildContext context, IconData icon, String title, String subtitle) {
    final c = context.allora;
    return ListTile(
      leading: Icon(icon, color: c.textTertiary),
      title: Row(
        children: [
          Flexible(child: Text(title, style: TextStyle(color: c.textSecondary))),
          const SizedBox(width: 8),
          _badge(c, 'SOON', c.textTertiary),
        ],
      ),
      subtitle: Text(subtitle),
      trailing: Icon(Icons.lock_clock_rounded, size: 18, color: c.textTertiary),
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This feature is coming in a future update.')),
      ),
    );
  }

  Widget _badge(AlloraColors c, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 9.5, fontWeight: FontWeight.w800, color: color)),
      );

  TextStyle _sectionStyle(AlloraColors c) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: c.textTertiary);
}

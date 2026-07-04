import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/settings/app_settings.dart';

class AccessibilitySettingsScreen extends ConsumerWidget {
  const AccessibilitySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.allora;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(title: const Text('Accessibility')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(context, [
            SwitchListTile(
              secondary: Icon(Icons.animation_rounded, color: c.textSecondary),
              title: const Text('Reduce motion'),
              subtitle: const Text(
                  'Minimise transition and interface animations'),
              value: settings.reduceMotion,
              onChanged: notifier.setReduceMotion,
            ),
            Divider(color: c.outline, height: 1),
            SwitchListTile(
              secondary: Icon(Icons.contrast_rounded, color: c.textSecondary),
              title: const Text('High contrast'),
              subtitle:
                  const Text('Stronger borders and text for readability'),
              value: settings.highContrast,
              onChanged: notifier.setHighContrast,
            ),
          ]),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('TEXT SIZE',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: c.textTertiary)),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.outline),
            ),
            child: Row(
              children: [
                Text('A', style: TextStyle(fontSize: 13, color: c.textSecondary)),
                Expanded(
                  child: Slider(
                    value: settings.fontScale,
                    min: 0.85,
                    max: 1.3,
                    divisions: 6,
                    label: '${(settings.fontScale * 100).round()}%',
                    onChanged: notifier.setFontScale,
                  ),
                ),
                Text('A', style: TextStyle(fontSize: 22, color: c.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Allora also respects your system font size and screen-reader '
              '(TalkBack) settings. Buttons, switches and images include '
              'semantic labels for assistive tech.',
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
}

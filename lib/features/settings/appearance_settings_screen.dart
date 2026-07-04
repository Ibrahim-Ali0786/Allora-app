import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/settings/app_settings.dart';

class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.allora;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('THEME', style: _label(c)),
          const SizedBox(height: 8),
          Row(
            children: [
              _themeOption(context, ref, ThemeMode.light, 'Light',
                  Icons.light_mode_rounded, settings.themeMode),
              const SizedBox(width: 10),
              _themeOption(context, ref, ThemeMode.dark, 'Dark',
                  Icons.dark_mode_rounded, settings.themeMode),
              const SizedBox(width: 10),
              _themeOption(context, ref, ThemeMode.system, 'Auto',
                  Icons.brightness_auto_rounded, settings.themeMode),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.outline),
            ),
            child: SwitchListTile(
              secondary: Icon(Icons.contrast_rounded, color: c.textSecondary),
              title: const Text('AMOLED black'),
              subtitle: const Text('Pure-black backgrounds in dark mode'),
              value: settings.amoledBlack,
              onChanged: (v) => notifier.setAmoledBlack(v),
            ),
          ),
          const SizedBox(height: 24),
          Text('ACCENT COLOR', style: _label(c)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (var i = 0; i < kAccentPresets.length; i++)
                GestureDetector(
                  onTap: () => notifier.setAccent(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        kAccentPresets[i].color,
                        kAccentPresets[i].deep,
                      ]),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: settings.accentIndex == i
                            ? c.text
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: settings.accentIndex == i
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 22)
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text('MESSAGE TEXT SIZE', style: _label(c)),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('A', style: TextStyle(fontSize: 13, color: c.textSecondary)),
              Expanded(
                child: Slider(
                  value: settings.fontScale,
                  min: 0.85,
                  max: 1.3,
                  divisions: 6,
                  label: '${(settings.fontScale * 100).round()}%',
                  onChanged: (v) => notifier.setFontScale(v),
                ),
              ),
              Text('A', style: TextStyle(fontSize: 22, color: c.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 9),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: [c.bubbleMine, c.bubbleMineDeep]),
                      borderRadius: BorderRadius.circular(16)
                          .copyWith(bottomRight: const Radius.circular(5)),
                    ),
                    child: Text('Preview message 👋',
                        style: TextStyle(
                            fontSize: 15.5 * settings.fontScale,
                            color: c.onAccent)),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 9),
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: BorderRadius.circular(16)
                          .copyWith(bottomLeft: const Radius.circular(5)),
                    ),
                    child: Text('This is how chats will look.',
                        style: TextStyle(
                            fontSize: 15.5 * settings.fontScale,
                            color: c.text)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _themeOption(BuildContext context, WidgetRef ref, ThemeMode mode,
      String label, IconData icon, ThemeMode current) {
    final c = context.allora;
    final selected = current == mode;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => ref.read(settingsProvider.notifier).setThemeMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: selected ? c.accent.withValues(alpha: 0.12) : c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? c.accent : c.outline),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? c.accent : c.textSecondary),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? c.accent : c.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _label(AlloraColors c) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: c.textTertiary);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/settings/app_settings.dart';
import '../privacy/app_lock.dart';

class SecuritySettingsScreen extends ConsumerWidget {
  const SecuritySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.allora;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(title: const Text('Security')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(Icons.lock_rounded, color: c.accent),
                  title: const Text('App lock'),
                  subtitle: const Text('Require a PIN to open Allora'),
                  value: settings.appLockEnabled,
                  onChanged: (v) async {
                    if (v) {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PinSetupScreen()),
                      );
                    } else {
                      notifier.disableAppLock();
                    }
                  },
                ),
                if (settings.appLockEnabled) ...[
                  Divider(color: c.outline, height: 1),
                  SwitchListTile(
                    secondary:
                        Icon(Icons.fingerprint_rounded, color: c.textSecondary),
                    title: const Text('Unlock with biometrics'),
                    subtitle: const Text('Fingerprint or face unlock'),
                    value: settings.biometricEnabled,
                    onChanged: notifier.setBiometric,
                  ),
                  Divider(color: c.outline, height: 1),
                  ListTile(
                    leading: Icon(Icons.timer_rounded, color: c.textSecondary),
                    title: const Text('Auto-lock'),
                    subtitle: Text(_autoLockLabel(settings.autoLockMinutes)),
                    trailing:
                        Icon(Icons.chevron_right_rounded, color: c.textTertiary),
                    onTap: () => _pickAutoLock(context, ref),
                  ),
                  Divider(color: c.outline, height: 1),
                  ListTile(
                    leading: Icon(Icons.password_rounded, color: c.textSecondary),
                    title: const Text('Change PIN'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PinSetupScreen()),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Your PIN is stored only on this device as a salted hash — '
              'it never leaves your phone. If you forget it, log out and '
              'sign back in.',
              style: TextStyle(
                  fontSize: 12.5, color: c.textTertiary, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  static String _autoLockLabel(int minutes) {
    if (minutes <= 0) return 'Immediately';
    if (minutes == 1) return 'After 1 minute';
    if (minutes < 60) return 'After $minutes minutes';
    return 'After 1 hour';
  }

  void _pickAutoLock(BuildContext context, WidgetRef ref) {
    final current = ref.read(settingsProvider).autoLockMinutes;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in [0, 1, 5, 15, 60])
              RadioListTile<int>(
                value: m,
                groupValue: current,
                title: Text(_autoLockLabel(m)),
                onChanged: (v) {
                  Navigator.pop(ctx);
                  if (v != null) {
                    ref.read(settingsProvider.notifier).setAutoLockMinutes(v);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

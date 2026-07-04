// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/allora_avatar.dart';
import '../../data/settings/app_settings.dart';
import '../../providers/network_provider.dart';
import '../chat_list/chat_list_providers.dart';
import '../privacy/app_lock.dart';

class PrivacySettingsScreen extends ConsumerWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.allora;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(context, [
            SwitchListTile(
              secondary: Icon(Icons.visibility_off_rounded, color: c.text),
              title: const Text('Incognito mode'),
              subtitle: const Text(
                  'One switch for everything below, plus screenshot '
                  'blocking and paused AI history'),
              value: settings.incognito,
              onChanged: notifier.setIncognito,
            ),
          ]),
          const SizedBox(height: 14),
          _card(context, [
            SwitchListTile(
              secondary:
                  Icon(Icons.keyboard_hide_rounded, color: c.textSecondary),
              title: const Text('Hide typing indicator'),
              subtitle: const Text('Others won\u2019t see when you\u2019re typing'),
              value: settings.effectiveHideTyping,
              onChanged:
                  settings.incognito ? null : notifier.setHideTyping,
            ),
            Divider(color: c.outline, height: 1),
            SwitchListTile(
              secondary: Icon(Icons.done_all_rounded, color: c.textSecondary),
              title: const Text('Hide read receipts'),
              subtitle: const Text(
                  'Chats stay marked unread for senders; unread badges '
                  'clear only on this device'),
              value: settings.effectiveHideReadReceipts,
              onChanged:
                  settings.incognito ? null : notifier.setHideReadReceipts,
            ),
            Divider(color: c.outline, height: 1),
            SwitchListTile(
              secondary:
                  Icon(Icons.screenshot_monitor_rounded, color: c.textSecondary),
              title: const Text('Block screenshots'),
              subtitle: const Text(
                  'Also hides Allora in the recent-apps switcher (Android)'),
              value: settings.effectiveBlockScreenshots,
              onChanged:
                  settings.incognito ? null : notifier.setBlockScreenshots,
            ),
            Divider(color: c.outline, height: 1),
            SwitchListTile(
              secondary:
                  Icon(Icons.auto_awesome_rounded, color: c.textSecondary),
              title: const Text('Keep AI history'),
              subtitle:
                  const Text('Store the Allora AI conversation on this device'),
              value: settings.effectiveAiHistory,
              onChanged:
                  settings.incognito ? null : notifier.setAiHistoryEnabled,
            ),
          ]),
          const SizedBox(height: 14),
          _card(context, [
            ListTile(
              leading: Icon(Icons.folder_off_rounded, color: c.textSecondary),
              title: const Text('Hidden chats'),
              subtitle: Text('${settings.hiddenChats.length} hidden'),
              trailing: Icon(Icons.chevron_right_rounded, color: c.textTertiary),
              onTap: () => _openHiddenChats(context, ref),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _openHiddenChats(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsProvider);
    // Gate behind the PIN when app lock is enabled.
    if (settings.appLockEnabled && settings.pinHash != null) {
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const _PinGateScreen(title: 'Hidden chats'),
        ),
      );
      if (ok != true) return;
    }
    if (context.mounted) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const _HiddenChatsScreen()));
    }
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

/// Self-contained PIN verification route; pops with `true` on success.
class _PinGateScreen extends ConsumerWidget {
  final String title;
  const _PinGateScreen({required this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      body: PinLockScreen(
        title: title,
        biometricAllowed: settings.biometricEnabled,
        onVerify: (pin) => ref.read(settingsProvider.notifier).verifyPin(pin),
        onUnlocked: () => Navigator.pop(context, true),
      ),
    );
  }
}

class _HiddenChatsScreen extends ConsumerWidget {
  const _HiddenChatsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.allora;
    final client = ref.watch(matrixClientProvider);
    final hidden = ref.watch(settingsProvider.select((s) => s.hiddenChats));

    final rooms = hidden
        .map(client.getRoomById)
        .whereType<Room>()
        .toList();

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(title: const Text('Hidden chats')),
      body: rooms.isEmpty
          ? Center(
              child: Text('No hidden chats',
                  style: TextStyle(color: c.textSecondary)))
          : ListView.builder(
              itemCount: rooms.length,
              itemBuilder: (context, i) {
                final room = rooms[i];
                final title = cleanRoomTitle(room.displayname);
                return ListTile(
                  leading: AlloraAvatar(
                    name: title,
                    mxcUri: room.avatar,
                    client: client,
                    size: 44,
                    showNetworkBadge: false,
                  ),
                  title: Text(title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: TextButton(
                    child: const Text('Unhide'),
                    onPressed: () => ref
                        .read(settingsProvider.notifier)
                        .setHidden(room.id, false),
                  ),
                );
              },
            ),
    );
  }
}

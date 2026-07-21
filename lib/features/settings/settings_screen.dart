import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/allora_avatar.dart';
import '../../data/services/account_lifecycle.dart';
import '../../data/services/ai_service.dart';
import '../../data/settings/app_settings.dart';
import '../../providers/network_provider.dart';
import '../../screens/auth/welcome_screen.dart';
import '../../screens/connection_screen/connect_networks_screen.dart';
import '../profile/profile_screen.dart';
import '../labels/labels_management_screen.dart';
import 'accessibility_settings_screen.dart';
import 'ai_settings_screen.dart';
import 'appearance_settings_screen.dart';
import 'diagnostics_screen.dart';
import 'floating_chat_settings_screen.dart';
import 'labs_settings_screen.dart';
import 'privacy_settings_screen.dart';
import 'scheduled_messages_screen.dart';
import 'security_settings_screen.dart';
import 'starred_messages_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    final client = ref.watch(matrixClientProvider);
    final settings = ref.watch(settingsProvider);
    final email = Supabase.instance.client.auth.currentUser?.email;
    final username =
        client.userID?.split(':').first.replaceAll('@', '') ?? 'You';

    final sections = <_SettingsSection>[
      _SettingsSection('General', [
        _Item(
          icon: Icons.hub_rounded,
          color: const Color(0xFF3A6FF8),
          title: 'Accounts',
          subtitle: 'Connect WhatsApp, Telegram, Instagram…',
          keywords: 'accounts networks bridge connect whatsapp telegram',
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ConnectNetworksScreen(client: client))),
        ),
        _Item(
          icon: Icons.palette_rounded,
          color: const Color(0xFF7C5CFC),
          title: 'Appearance',
          subtitle: 'Theme, accent color, text size',
          keywords: 'appearance theme dark light accent font size',
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const AppearanceSettingsScreen())),
        ),
        _Item(
          icon: Icons.notifications_rounded,
          color: const Color(0xFFE8930C),
          title: 'Notifications',
          subtitle: 'Per-chat muting and alerts',
          keywords: 'notifications mute alerts sound',
          onTap: _showNotificationsInfo,
        ),
        _Item(
          icon: Icons.accessibility_new_rounded,
          color: const Color(0xFF00A3AD),
          title: 'Accessibility',
          subtitle: 'Reduce motion, high contrast, text size',
          keywords: 'accessibility reduce motion contrast text size a11y',
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const AccessibilitySettingsScreen())),
        ),
        _Item(
          icon: Icons.bubble_chart_rounded,
          color: const Color(0xFF7C5CFC),
          title: 'Floating chat',
          subtitle: 'Chat bubble over other apps',
          keywords: 'floating chat bubble overlay heads over apps',
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const FloatingChatSettingsScreen())),
        ),
      ]),
      _SettingsSection('Privacy & Security', [
        _Item(
          icon: Icons.visibility_off_rounded,
          color: const Color(0xFF17181C),
          darkColor: const Color(0xFFA0A2AB),
          title: 'Privacy & Incognito',
          subtitle: settings.incognito
              ? 'Incognito is ON'
              : 'Typing, read receipts, hidden chats',
          keywords:
              'privacy incognito typing read receipts hidden chats screenshots',
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const PrivacySettingsScreen())),
        ),
        _Item(
          icon: Icons.lock_rounded,
          color: const Color(0xFF1FA45B),
          title: 'Security',
          subtitle: settings.appLockEnabled
              ? 'App lock is on'
              : 'PIN, fingerprint, auto-lock',
          keywords: 'security lock pin fingerprint biometric face',
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const SecuritySettingsScreen())),
        ),
      ]),
      _SettingsSection('Messaging', [
        _Item(
          icon: Icons.auto_awesome_rounded,
          color: const Color(0xFFE45794),
          title: 'AI Assistant',
          subtitle: settings.aiEnabled ? 'Allora AI is on' : 'Turned off',
          keywords: 'ai assistant smart reply rewrite translate allora',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AiSettingsScreen())),
        ),
        _Item(
          icon: Icons.star_rounded,
          color: const Color(0xFFF5A623),
          title: 'Starred messages',
          subtitle: '${settings.starred.length} saved',
          keywords: 'starred bookmarks favorites saved messages',
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const StarredMessagesScreen())),
        ),
        _Item(
          icon: Icons.schedule_send_rounded,
          color: const Color(0xFF00A3AD),
          title: 'Scheduled messages',
          subtitle: 'Messages waiting to send',
          keywords: 'scheduled send later timer messages',
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ScheduledMessagesScreen())),
        ),
        _Item(
          icon: Icons.label_rounded,
          color: const Color(0xFF7C5CFC),
          title: 'Labels',
          subtitle: 'Organise chats into colour-coded labels',
          keywords: 'labels folders categories tags organise color',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const LabelsManagementScreen())),
        ),
      ]),
      _SettingsSection('Data', [
        _Item(
          icon: Icons.storage_rounded,
          color: const Color(0xFF6E7076),
          title: 'Storage',
          subtitle: 'Cache and local data',
          keywords: 'storage cache clear data size',
          onTap: _showStorageSheet,
        ),
        _Item(
          icon: Icons.science_rounded,
          color: const Color(0xFFE45794),
          title: 'Labs',
          subtitle: 'Experimental features',
          keywords: 'labs experimental beta features ai floating',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const LabsSettingsScreen())),
        ),
        _Item(
          icon: Icons.monitor_heart_rounded,
          color: const Color(0xFF1FA45B),
          title: 'Diagnostics',
          subtitle: 'Connection, storage & bridge status',
          keywords: 'diagnostics debug status bridge database version export',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const DiagnosticsScreen())),
        ),
        _Item(
          icon: Icons.info_rounded,
          color: const Color(0xFF5C7CDB),
          title: 'About Allora',
          subtitle: 'Version 2.0.0',
          keywords: 'about version licenses',
          onTap: _showAbout,
        ),
      ]),
    ];

    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? sections
        : sections
            .map((s) => _SettingsSection(
                s.title,
                s.items
                    .where((i) =>
                        i.title.toLowerCase().contains(q) ||
                        i.keywords.contains(q))
                    .toList()))
            .where((s) => s.items.isNotEmpty)
            .toList();

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Search settings…',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 14),
          if (q.isEmpty) ...[
            _profileCard(username, email),
            const SizedBox(height: 12),
            _incognitoCard(settings.incognito),
            const SizedBox(height: 4),
          ],
          for (final section in filtered) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
              child: Text(section.title.toUpperCase(),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: c.textTertiary)),
            ),
            _card([
              for (var i = 0; i < section.items.length; i++) ...[
                if (i > 0)
                  Divider(color: c.outline, height: 1, indent: 62),
                _tile(section.items[i]),
              ],
            ]),
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: c.danger,
              side: BorderSide(color: c.danger.withValues(alpha: 0.4)),
            ),
            onPressed: _confirmLogout,
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Log out of Allora'),
          ),
        ],
      ),
    );
  }

  Widget _profileCard(String username, String? email) {
    final c = context.allora;
    return _card([
      InkWell(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ProfileScreen())),
        child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            AlloraAvatar(name: username, size: 52, showNetworkBadge: false),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: c.text)),
                  if (email != null)
                    Text(email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13, color: c.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.textTertiary),
          ],
        ),
      ),
      ),
    ]);
  }

  Widget _incognitoCard(bool incognito) {
    final c = context.allora;
    return _card([
      SwitchListTile(
        secondary: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: c.text.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(Icons.visibility_off_rounded, color: c.canvas, size: 19),
        ),
        title: const Text('Incognito mode'),
        subtitle: const Text('Hide typing & read receipts, block '
            'screenshots, pause AI history'),
        value: incognito,
        onChanged: (v) =>
            ref.read(settingsProvider.notifier).setIncognito(v),
      ),
    ]);
  }

  Widget _tile(_Item item) {
    final c = context.allora;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = dark && item.darkColor != null ? item.darkColor! : item.color;
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(item.icon, color: color, size: 19),
      ),
      title: Text(item.title),
      subtitle: Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Icon(Icons.chevron_right_rounded, color: c.textTertiary),
      onTap: item.onTap,
    );
  }

  Widget _card(List<Widget> children) {
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

  // ── Sheets & dialogs ──────────────────────────────────────────────────────

  void _showNotificationsInfo() {
    final c = context.allora;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Notifications',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: c.text)),
              const SizedBox(height: 12),
              Text(
                '• Mute any chat from its long-press menu or chat details — '
                'muted chats never raise an alert.\n\n'
                '• While Allora is open, new messages appear instantly via '
                'the live connection.\n\n'
                '• Push notifications for a closed app require the Allora '
                'push gateway, which rolls out with a server update — no '
                'setup needed in the app.',
                style: TextStyle(
                    fontSize: 13.5, color: c.textSecondary, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showStorageSheet() async {
    final c = context.allora;
    int dbBytes = 0;
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File(p.join(dir.path, 'allora_matrix.db'));
      if (f.existsSync()) dbBytes = f.lengthSync();
    } catch (_) {}
    final imgBytes = PaintingBinding.instance.imageCache.currentSizeBytes;
    if (!mounted) return;

    String fmt(int b) => b > 1048576
        ? '${(b / 1048576).toStringAsFixed(1)} MB'
        : '${(b / 1024).toStringAsFixed(0)} KB';

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Storage',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: c.text)),
              const SizedBox(height: 14),
              _storageRow(ctx, 'Message database', fmt(dbBytes)),
              _storageRow(ctx, 'Image cache (memory)', fmt(imgBytes)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        PaintingBinding.instance.imageCache.clear();
                        PaintingBinding.instance.imageCache
                            .clearLiveImages();
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Image cache cleared')));
                      },
                      child: const Text('Clear image cache'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        await AiChatStore.clear();
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('AI history cleared')));
                        }
                      },
                      child: const Text('Clear AI history'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _storageRow(BuildContext ctx, String label, String value) {
    final c = ctx.allora;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 14, color: c.textSecondary))),
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
        ],
      ),
    );
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'Allora',
      applicationVersion: '2.0.0',
      applicationLegalese: 'One inbox for every conversation.\n'
          'Built on Matrix — your messages, your server.',
      applicationIcon: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            context.allora.accent,
            context.allora.bubbleMineDeep,
          ]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.forum_rounded, color: Colors.white),
      ),
    );
  }

  void _confirmLogout() {
    final c = context.allora;
    final client = ref.read(matrixClientProvider);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out of Allora?'),
        content: Text(
          'Your connected networks stay linked to your account. You\u2019ll '
          'need to sign in again to see your messages.',
          style: TextStyle(color: c.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await AccountLifecycleService.logoutAllora(client);
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                      builder: (_) => WelcomeScreen(client: client)),
                  (r) => false,
                );
              }
            },
            child: Text('Log out', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection {
  final String title;
  final List<_Item> items;
  const _SettingsSection(this.title, this.items);
}

class _Item {
  final IconData icon;
  final Color color;
  final Color? darkColor;
  final String title;
  final String subtitle;
  final String keywords;
  final VoidCallback onTap;

  const _Item({
    required this.icon,
    required this.color,
    this.darkColor,
    required this.title,
    required this.subtitle,
    required this.keywords,
    required this.onTap,
  });
}

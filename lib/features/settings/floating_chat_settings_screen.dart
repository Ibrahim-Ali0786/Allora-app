import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/floating_chat_service.dart';
import '../../data/settings/app_settings.dart';

class FloatingChatSettingsScreen extends ConsumerStatefulWidget {
  const FloatingChatSettingsScreen({super.key});

  @override
  ConsumerState<FloatingChatSettingsScreen> createState() =>
      _FloatingChatSettingsScreenState();
}

class _FloatingChatSettingsScreenState
    extends ConsumerState<FloatingChatSettingsScreen> with WidgetsBindingObserver {
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check after the user returns from the system permission screen.
    if (state == AppLifecycleState.resumed) _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final granted = await FloatingChatService.hasPermission();
    if (mounted) setState(() => _hasPermission = granted);
  }

  Future<void> _toggle(bool value) async {
    if (value && !_hasPermission) {
      await FloatingChatService.requestPermission();
      // Permission is granted on the system screen; we re-check on resume.
      return;
    }
    ref.read(settingsProvider.notifier).setFloatingChatEnabled(value);
    if (!value) await FloatingChatService.hide();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    final enabled =
        ref.watch(settingsProvider.select((s) => s.floatingChatEnabled));

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(title: const Text('Floating chat')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
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
                const Icon(Icons.bubble_chart_rounded,
                    color: Colors.white, size: 34),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Chat bubbles',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      SizedBox(height: 3),
                      Text(
                        'A floating bubble stays on top of other apps, shows '
                        'your unread count, and opens Allora with one tap.',
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
                  secondary: Icon(Icons.bubble_chart_rounded, color: c.accent),
                  title: const Text('Enable chat bubble'),
                  subtitle: Text(_hasPermission
                      ? 'Shows when you leave the app'
                      : 'Requires "display over other apps" permission'),
                  value: enabled && _hasPermission,
                  onChanged: _toggle,
                ),
                if (!_hasPermission) ...[
                  Divider(color: c.outline, height: 1),
                  ListTile(
                    leading:
                        Icon(Icons.shield_outlined, color: c.textSecondary),
                    title: const Text('Grant overlay permission'),
                    subtitle:
                        const Text('Allow Allora to display over other apps'),
                    trailing: Icon(Icons.open_in_new_rounded,
                        size: 18, color: c.textTertiary),
                    onTap: () => FloatingChatService.requestPermission(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Drag the bubble anywhere — it snaps to the nearest edge. Tap it '
              'to jump back into Allora. Turn it off here anytime.',
              style:
                  TextStyle(fontSize: 12.5, color: c.textTertiary, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

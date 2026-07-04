// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/allora_avatar.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/services/connection_manager.dart';
import '../../data/services/disappearing_message_service.dart';
import '../../data/services/room_wipe_service.dart';
import '../../data/settings/app_settings.dart';
import '../../data/settings/labels.dart';
import '../labels/labels_management_screen.dart';
import '../../providers/network_provider.dart';
import '../../screens/connect_networks_screen.dart';
import '../ai/ai_chat_screen.dart';
import '../chat/chat_screen.dart';
import '../chat/widgets/disappearing_sheet.dart';
import '../search/global_search_screen.dart';
import '../settings/settings_screen.dart';
import 'archived_chats_screen.dart';
import 'chat_list_providers.dart';
import 'widgets/chat_tile.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  bool _searchOpen = false;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // One connection probe on entry — after this, everything is stream-fed.
    Future.microtask(
        () => ref.read(connectionManagerProvider.notifier).probeNetworks());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() => _searchOpen = !_searchOpen);
    if (_searchOpen) {
      _searchFocus.requestFocus();
    } else {
      _searchController.clear();
      ref.read(chatSearchQueryProvider.notifier).state = '';
    }
  }

  void _openChat(ChatEntry entry) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(room: entry.room)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    final client = ref.watch(matrixClientProvider);
    final data = ref.watch(chatListProvider);
    final conn = ref.watch(connectionManagerProvider);
    final incognito = ref.watch(settingsProvider.select((s) => s.incognito));
    final wiping = ref.watch(wipePendingProvider);
    final firstSyncDone = client.prevBatch != null;

    return Scaffold(
      backgroundColor: c.canvas,
      floatingActionButton: FloatingActionButton(
        heroTag: 'compose_fab',
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const GlobalSearchScreen())),
        child: const Icon(Icons.edit_rounded),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              incognito: incognito,
              matrixState: conn.matrix,
              totalUnread: data.totalUnread,
              searchOpen: _searchOpen,
              onToggleSearch: _toggleSearch,
              onOpenSettings: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen())),
              onOpenNetworks: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ConnectNetworksScreen(client: client))),
            ),
            _SearchField(
              open: _searchOpen,
              controller: _searchController,
              focusNode: _searchFocus,
              onChanged: (v) =>
                  ref.read(chatSearchQueryProvider.notifier).state = v,
            ),
            const _FilterChips(),
            if (wiping.isNotEmpty) _WipeBanner(count: wiping.length),
            if (!conn.matrix.isHealthy && conn.matrix != ConnState.connecting)
              _ConnectionBanner(state: conn.matrix),
            Expanded(
              child: !firstSyncDone
                  ? const ChatListSkeleton()
                  : data.isEmpty
                      ? _emptyState(client)
                      : _list(data),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(Client client) {
    final query = ref.watch(chatSearchQueryProvider);
    if (query.trim().isNotEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No results',
        message: 'No chats match "$query".',
      );
    }
    return EmptyState(
      icon: Icons.forum_rounded,
      title: 'Your inbox is quiet',
      message:
          'Connect WhatsApp, Telegram, Instagram and more to read and reply '
          'to everything from one place.',
      actionLabel: 'Connect a network',
      onAction: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ConnectNetworksScreen(client: client))),
    );
  }

  Widget _list(ChatListData data) {
    final showAiRow = ref.watch(settingsProvider.select((s) => s.aiEnabled)) &&
        ref.watch(chatSearchQueryProvider).trim().isEmpty &&
        ref.watch(chatFilterProvider) == ChatFilter.all &&
        ref.watch(networkFilterProvider) == null;

    final rows = <Widget>[
      if (showAiRow) const _AlloraAiRow(),
      if (data.pinned.isNotEmpty) ...[
        _SectionLabel(icon: Icons.push_pin_rounded, label: 'Pinned'),
        for (final entry in data.pinned) _tile(entry),
        if (data.chats.isNotEmpty)
          _SectionLabel(icon: Icons.chat_bubble_rounded, label: 'Chats'),
      ],
      for (final entry in data.chats) _tile(entry),
      if (data.archivedCount > 0) _archivedRow(data.archivedCount),
      const SizedBox(height: 96), // FAB clearance
    ];

    return ListView.builder(
      physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics()),
      itemCount: rows.length,
      itemBuilder: (context, i) => rows[i],
      // Rows are cheap; keep a healthy cache so fast flings never blank.
      cacheExtent: 600,
    );
  }

  Widget _tile(ChatEntry entry) {
    final c = context.allora;
    return RepaintBoundary(
      key: ValueKey(entry.room.id),
      child: Dismissible(
        key: ValueKey('swipe_${entry.room.id}'),
        confirmDismiss: (direction) async {
          HapticFeedback.lightImpact();
          if (direction == DismissDirection.startToEnd) {
            await _toggleRead(entry);
            return false; // snap back — it's an action, not a removal
          }
          _archive(entry);
          return false;
        },
        background: _SwipeAction(
          alignment: Alignment.centerLeft,
          color: c.accent,
          icon: entry.isUnread
              ? Icons.mark_chat_read_rounded
              : Icons.mark_chat_unread_rounded,
          label: entry.isUnread ? 'Read' : 'Unread',
        ),
        secondaryBackground: _SwipeAction(
          alignment: Alignment.centerRight,
          color: c.textSecondary,
          icon: Icons.archive_rounded,
          label: 'Archive',
        ),
        child: ChatTile(
          entry: entry,
          onTap: () => _openChat(entry),
          onLongPress: () => _showChatMenu(entry),
        ),
      ),
    );
  }

  Widget _archivedRow(int count) {
    final c = context.allora;
    return InkWell(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const ArchivedChatsScreen())),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration:
                  BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
              child: Icon(Icons.archive_rounded, color: c.textSecondary),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text('Archived',
                  style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: c.textSecondary)),
            ),
            Text('$count',
                style: TextStyle(fontSize: 13, color: c.textTertiary)),
            Icon(Icons.chevron_right_rounded, color: c.textTertiary),
          ],
        ),
      ),
    );
  }

  // ── Row actions ───────────────────────────────────────────────────────────

  Future<void> _toggleRead(ChatEntry entry) async {
    final room = entry.room;
    try {
      if (entry.isUnread) {
        final last = room.lastEvent;
        if (last != null &&
            !ref.read(settingsProvider).effectiveHideReadReceipts) {
          await room.setReadMarker(last.eventId, mRead: last.eventId);
        }
        await room.markUnread(false);
      } else {
        await room.markUnread(true);
      }
    } catch (e) {
      debugPrint('toggleRead failed: $e');
    }
  }

  void _archive(ChatEntry entry) {
    ref.read(settingsProvider.notifier).setArchived(entry.room.id, true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${entry.title} archived'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => ref
            .read(settingsProvider.notifier)
            .setArchived(entry.room.id, false),
      ),
    ));
  }

  void _showChatMenu(ChatEntry entry) {
    HapticFeedback.mediumImpact();
    final c = context.allora;
    final settings = ref.read(settingsProvider.notifier);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  AlloraAvatar(
                    name: entry.title,
                    mxcUri: entry.room.avatar,
                    client: entry.room.client,
                    size: 40,
                    network: entry.network,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: c.text)),
                  ),
                ],
              ),
            ),
            Divider(color: c.outline),
            _menuItem(
              ctx,
              icon: entry.pinned
                  ? Icons.push_pin_outlined
                  : Icons.push_pin_rounded,
              label: entry.pinned ? 'Unpin' : 'Pin chat',
              onTap: () => settings.togglePinned(entry.room.id),
            ),
            _menuItem(
              ctx,
              icon: entry.muted
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_rounded,
              label: entry.muted ? 'Unmute' : 'Mute',
              onTap: () async {
                try {
                  await entry.room.setPushRuleState(entry.muted
                      ? PushRuleState.notify
                      : PushRuleState.dontNotify);
                } catch (e) {
                  debugPrint('mute failed: $e');
                }
              },
            ),
            _menuItem(
              ctx,
              icon: entry.isUnread
                  ? Icons.mark_chat_read_rounded
                  : Icons.mark_chat_unread_rounded,
              label: entry.isUnread ? 'Mark as read' : 'Mark as unread',
              onTap: () => _toggleRead(entry),
            ),
            _menuItem(
              ctx,
              icon: Icons.timer_outlined,
              label: 'Disappearing messages',
              trailing: DisappearingMessageService.labelFor(ref
                  .read(settingsProvider)
                  .disappearingSeconds[entry.room.id] ??
                  0),
              onTap: () => showDisappearingSheet(context, ref, entry.room),
            ),
            _menuItem(
              ctx,
              icon: Icons.label_outline_rounded,
              label: 'Labels',
              trailing: entry.labels.isEmpty
                  ? null
                  : entry.labels.map((l) => l.name).join(', '),
              onTap: () => showAssignLabelsSheet(
                  context, ref, entry.room.id, entry.title),
            ),
            _menuItem(
              ctx,
              icon: Icons.archive_outlined,
              label: 'Archive',
              onTap: () => _archive(entry),
            ),
            _menuItem(
              ctx,
              icon: Icons.visibility_off_outlined,
              label: 'Hide chat',
              onTap: () {
                settings.setHidden(entry.room.id, true);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        'Hidden. Reveal it from Settings → Privacy → Hidden chats.')));
              },
            ),
            _menuItem(
              ctx,
              icon: Icons.delete_outline_rounded,
              label: 'Delete chat',
              destructive: true,
              onTap: () => _confirmDelete(entry),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(
    BuildContext sheetContext, {
    required IconData icon,
    required String label,
    String? trailing,
    bool destructive = false,
    required VoidCallback onTap,
  }) {
    final c = context.allora;
    final color = destructive ? c.danger : c.text;
    return ListTile(
      leading: Icon(icon, color: destructive ? c.danger : c.textSecondary),
      title: Text(label,
          style: TextStyle(
              color: color, fontSize: 15, fontWeight: FontWeight.w500)),
      trailing: trailing != null
          ? Text(trailing,
              style: TextStyle(color: c.textTertiary, fontSize: 13))
          : null,
      onTap: () {
        Navigator.pop(sheetContext);
        onTap();
      },
    );
  }

  void _confirmDelete(ChatEntry entry) {
    final c = context.allora;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete chat?'),
        content: Text(
          'This removes "${entry.title}" from Allora. If the conversation is '
          'bridged, it stays on the original network.',
          style: TextStyle(color: c.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await RoomWipeService.enqueue(
                  entry.room.client, [entry.room.id]);
              ref.read(settingsProvider.notifier).forgetRooms([entry.room.id]);
              ref.read(labelsProvider.notifier).forgetRooms([entry.room.id]);
            },
            child: Text('Delete', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
  }
}

// ─── Header ────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final bool incognito;
  final ConnState matrixState;
  final int totalUnread;
  final bool searchOpen;
  final VoidCallback onToggleSearch;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenNetworks;

  const _Header({
    required this.incognito,
    required this.matrixState,
    required this.totalUnread,
    required this.searchOpen,
    required this.onToggleSearch,
    required this.onOpenSettings,
    required this.onOpenNetworks,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Chats',
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: c.text)),
                    if (incognito) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: c.text.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.visibility_off_rounded,
                                size: 12, color: c.canvas),
                            const SizedBox(width: 4),
                            Text('Incognito',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: c.canvas)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: matrixState == ConnState.connected
                      ? const SizedBox(height: 0, key: ValueKey('ok'))
                      : Padding(
                          key: ValueKey(matrixState),
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            matrixState.label,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: matrixState == ConnState.error ||
                                        matrixState == ConnState.expired
                                    ? c.danger
                                    : c.textSecondary),
                          ),
                        ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onToggleSearch,
            tooltip: 'Search',
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(
                searchOpen ? Icons.close_rounded : Icons.search_rounded,
                key: ValueKey(searchOpen),
                color: c.text,
              ),
            ),
          ),
          IconButton(
            onPressed: onOpenNetworks,
            tooltip: 'Connect networks',
            icon: Icon(Icons.hub_outlined, color: c.text),
          ),
          IconButton(
            onPressed: onOpenSettings,
            tooltip: 'Settings',
            icon: Icon(Icons.settings_outlined, color: c.text),
          ),
        ],
      ),
    );
  }
}

// ─── Search field ──────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final bool open;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  const _SearchField({
    required this.open,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: open
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search chats…',
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                ),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}

// ─── Filter chips ──────────────────────────────────────────────────────────

class _FilterChips extends ConsumerWidget {
  const _FilterChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.allora;
    final filter = ref.watch(chatFilterProvider);
    final networkFilter = ref.watch(networkFilterProvider);
    final networkState = ref.watch(networkHubProvider);
    final connected = networkState.networks
        .where((n) => n.status == NetworkStatus.connected)
        .map((n) => n.meta)
        .toList();

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          for (final f in ChatFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _chip(
                context,
                label: f.label,
                selected: filter == f &&
                    networkFilter == null &&
                    ref.watch(labelFilterProvider) == null,
                onTap: () {
                  ref.read(chatFilterProvider.notifier).state = f;
                  ref.read(networkFilterProvider.notifier).state = null;
                  ref.read(labelFilterProvider.notifier).state = null;
                },
              ),
            ),
          if (connected.isNotEmpty)
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              color: c.outline,
            ),
          for (final meta in connected)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _chip(
                context,
                label: meta.displayName,
                dotColor: meta.brandColor,
                selected: networkFilter == meta.id,
                onTap: () {
                  final current = ref.read(networkFilterProvider);
                  ref.read(networkFilterProvider.notifier).state =
                      current == meta.id ? null : meta.id;
                  ref.read(chatFilterProvider.notifier).state = ChatFilter.all;
                  ref.read(labelFilterProvider.notifier).state = null;
                },
              ),
            ),
          ..._labelChips(context, ref),
        ],
      ),
    );
  }

  List<Widget> _labelChips(BuildContext context, WidgetRef ref) {
    final c = context.allora;
    final labels = ref.watch(labelsProvider).sorted;
    final labelFilter = ref.watch(labelFilterProvider);
    return [
      Container(
        width: 1,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        color: c.outline,
      ),
      for (final label in labels)
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: _chip(
            context,
            label: label.name,
            dotColor: label.color,
            selected: labelFilter == label.id,
            onTap: () {
              final current = ref.read(labelFilterProvider);
              ref.read(labelFilterProvider.notifier).state =
                  current == label.id ? null : label.id;
              ref.read(chatFilterProvider.notifier).state = ChatFilter.all;
              ref.read(networkFilterProvider.notifier).state = null;
            },
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(left: 8, right: 4),
        child: GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const LabelsManagementScreen())),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.outline),
            ),
            child: Row(
              children: [
                Icon(Icons.add_rounded, size: 15, color: c.textSecondary),
                const SizedBox(width: 4),
                Text('Labels',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? dotColor,
  }) {
    final c = context.allora;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.accent : c.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            if (dotColor != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? c.onAccent : c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Banners & bits ────────────────────────────────────────────────────────

class _WipeBanner extends StatelessWidget {
  final int count;
  const _WipeBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Removing $count disconnected ${count == 1 ? 'chat' : 'chats'}…',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: c.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  final ConnState state;
  const _ConnectionBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    final isError = state == ConnState.error || state == ConnState.expired;
    final color = isError ? c.danger : c.warning;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.cloud_off_rounded : Icons.sync_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              state == ConnState.expired
                  ? 'Session expired — please sign in again'
                  : state == ConnState.error
                      ? 'Can\u2019t reach Allora — retrying automatically'
                      : state.label,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Row(
        children: [
          Icon(icon, size: 13, color: c.textTertiary),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: c.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeAction extends StatelessWidget {
  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  const _SwipeAction({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Entry row for the built-in Allora AI assistant.
class _AlloraAiRow extends StatelessWidget {
  const _AlloraAiRow();

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    return InkWell(
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const AiChatScreen())),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [c.accent, c.bubbleMineDeep],
                ),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 24),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Allora AI',
                      style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: c.text)),
                  const SizedBox(height: 3),
                  Text(
                    'Ask anything · rewrite · translate · summarize',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, color: c.textTertiary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}

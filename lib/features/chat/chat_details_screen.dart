// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/matrix_media.dart';
import '../../core/widgets/allora_avatar.dart';
import '../../data/services/disappearing_message_service.dart';
import '../../data/services/room_wipe_service.dart';
import '../../data/settings/app_settings.dart';
import '../../data/settings/labels.dart';
import '../../screens/bridge/bridge_room_classifier.dart';
import '../../screens/networks/network_meta.dart';
import '../chat_list/chat_list_providers.dart';
import 'widgets/disappearing_sheet.dart';
import 'widgets/image_viewer.dart';

/// Chat profile: hero avatar, quick toggles (mute / pin / archive / hide),
/// disappearing timer, shared media grid, members (for groups) and
/// leave/delete.
class ChatDetailsScreen extends ConsumerStatefulWidget {
  final Room room;
  const ChatDetailsScreen({super.key, required this.room});

  @override
  ConsumerState<ChatDetailsScreen> createState() => _ChatDetailsScreenState();
}

class _ChatDetailsScreenState extends ConsumerState<ChatDetailsScreen> {
  List<Event> _media = const [];
  bool _loadingMedia = true;

  Room get room => widget.room;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    try {
      final timeline = await room.getTimeline();
      if (timeline.canRequestHistory) {
        await timeline.requestHistory(historyCount: 120);
      }
      final media = timeline.events
          .where((e) =>
              !e.redacted &&
              e.content['msgtype'] == 'm.image' &&
              e.content['url'] is String)
          .take(30)
          .toList();
      timeline.cancelSubscriptions();
      if (mounted) {
        setState(() {
          _media = media;
          _loadingMedia = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMedia = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    final settings = ref.watch(settingsProvider);
    final title = cleanRoomTitle(room.displayname);
    final networkId = BridgeRoomClassifier.getNetworkForRoom(room,
        client: room.client);
    final network = networkId != null ? metaFor(networkId) : null;
    final muted = room.pushRuleState == PushRuleState.dontNotify;
    final pinned = settings.pinnedChats.contains(room.id);
    final archived = settings.archivedChats.contains(room.id);
    final ttl = settings.disappearingSeconds[room.id] ?? 0;
    final members = room.getParticipants()
      ..sort((a, b) => a.calcDisplayname().compareTo(b.calcDisplayname()));

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Center(
            child: Column(
              children: [
                Hero(
                  tag: 'avatar_${room.id}',
                  child: AlloraAvatar(
                    name: title,
                    mxcUri: room.avatar,
                    client: room.client,
                    size: 96,
                    network: network,
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: c.text),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  network != null
                      ? '${network.displayName} · ${room.isDirectChat ? 'Direct message' : '${members.length} members'}'
                      : room.isDirectChat
                          ? 'Direct message'
                          : '${members.length} members',
                  style: TextStyle(fontSize: 13.5, color: c.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _quickAction(
                  icon: muted
                      ? Icons.notifications_off_rounded
                      : Icons.notifications_active_rounded,
                  label: muted ? 'Muted' : 'Mute',
                  active: muted,
                  onTap: () async {
                    try {
                      await room.setPushRuleState(muted
                          ? PushRuleState.notify
                          : PushRuleState.dontNotify);
                      setState(() {});
                    } catch (_) {}
                  },
                ),
                _quickAction(
                  icon: Icons.push_pin_rounded,
                  label: pinned ? 'Pinned' : 'Pin',
                  active: pinned,
                  onTap: () =>
                      ref.read(settingsProvider.notifier).togglePinned(room.id),
                ),
                _quickAction(
                  icon: Icons.archive_rounded,
                  label: archived ? 'Archived' : 'Archive',
                  active: archived,
                  onTap: () => ref
                      .read(settingsProvider.notifier)
                      .setArchived(room.id, !archived),
                ),
                _quickAction(
                  icon: Icons.visibility_off_rounded,
                  label: 'Hide',
                  active: false,
                  onTap: () {
                    ref.read(settingsProvider.notifier).setHidden(room.id, true);
                    Navigator.popUntil(context, (r) => r.isFirst);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _card(children: [
            ListTile(
              leading: Icon(Icons.timer_outlined, color: c.textSecondary),
              title: const Text('Disappearing messages'),
              subtitle: Text(DisappearingMessageService.labelFor(ttl)),
              trailing: Icon(Icons.chevron_right_rounded, color: c.textTertiary),
              onTap: () => showDisappearingSheet(context, ref, room),
            ),
          ]),
          if (_loadingMedia || _media.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
              child: Text('SHARED MEDIA',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: c.textTertiary)),
            ),
            SizedBox(
              height: 92,
              child: _loadingMedia
                  ? const Center(
                      child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _media.length,
                      itemBuilder: (context, i) {
                        final event = _media[i];
                        final mxc = MatrixMedia.mxcOf(event);
                        final thumb = MatrixMedia.thumbnail(room.client, mxc,
                            width: 300, height: 300);
                        final full = MatrixMedia.download(room.client, mxc);
                        if (thumb == null || full == null) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).push(
                                ImageViewerScreen.route(
                                    url: full.url,
                                    headers: full.headers,
                                    heroTag: 'media_${event.eventId}')),
                            child: Hero(
                              tag: 'media_${event.eventId}',
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(thumb.url,
                                    headers: thumb.headers,
                                    width: 92,
                                    height: 92,
                                    cacheWidth: 300,
                                    fit: BoxFit.cover),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
          if (!room.isDirectChat) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 4),
              child: Text('MEMBERS · ${members.length}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: c.textTertiary)),
            ),
            _card(children: [
              for (final m in members.take(30))
                ListTile(
                  leading: AlloraAvatar(
                    name: m.calcDisplayname(),
                    mxcUri: m.avatarUrl,
                    client: room.client,
                    size: 38,
                    showNetworkBadge: false,
                  ),
                  title: Text(m.calcDisplayname(),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              if (members.length > 30)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('+ ${members.length - 30} more',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 13, color: c.textTertiary)),
                ),
            ]),
          ],
          const SizedBox(height: 18),
          _card(children: [
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: c.danger),
              title: Text('Delete chat',
                  style: TextStyle(color: c.danger)),
              onTap: _confirmDelete,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final c = context.allora;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: active ? c.accent.withValues(alpha: 0.12) : c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: active ? c.accent : c.outline),
            ),
            child: Column(
              children: [
                Icon(icon, size: 20, color: active ? c.accent : c.textSecondary),
                const SizedBox(height: 5),
                Text(label,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: active ? c.accent : c.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    final c = context.allora;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  void _confirmDelete() {
    final c = context.allora;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete chat?'),
        content: Text(
          'This removes the conversation from Allora. Bridged conversations '
          'remain on the original network.',
          style: TextStyle(color: c.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await RoomWipeService.enqueue(room.client, [room.id]);
              ref.read(settingsProvider.notifier).forgetRooms([room.id]);
              ref.read(labelsProvider.notifier).forgetRooms([room.id]);
              if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
            },
            child: Text('Delete', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
  }
}

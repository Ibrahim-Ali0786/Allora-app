// ignore_for_file: deprecated_member_use, depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import '../providers/network_provider.dart';
import './bridge/bridge_room_classifier.dart';
import './networks/network_meta.dart';
import 'chat_screen.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  List<Room> _getFilteredRooms(Client client, NetworkHubState networkState) {
    final connectedNetworks = networkState.networks
        .where((n) => n.status == NetworkStatus.connected)
        .map((n) => n.meta.id)
        .toSet();

    return client.rooms.where((room) {
      if (room.membership != Membership.join) return false;
      if (room.isSpace) return false;

      final networkId =
          BridgeRoomClassifier.getNetworkForRoom(room, client: client);

      if (networkId != null) {
        if (room.displayname
            .toLowerCase()
            .contains(metaFor(networkId).botAlias)) {
          return false;
        }
        return connectedNetworks.contains(networkId);
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final aTime = a.lastEvent?.originServerTs ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.lastEvent?.originServerTs ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
  }

  /// Enterprise-grade time formatter (e.g., "10:42 AM", "Yesterday", "10/12/23")
  String _formatTime(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inDays == 0 && now.day == time.day) {
      final hour =
          time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
      final amPm = time.hour >= 12 ? 'PM' : 'AM';
      return '$hour:${time.minute.toString().padLeft(2, '0')} $amPm';
    }
    if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[time.weekday - 1];
    }
    return '${time.month}/${time.day}/${time.year.toString().substring(2)}';
  }

  /// Safely extracts the last message without crashing on media events
  String _getPreviewText(Room room) {
    final event = room.lastEvent;
    if (event == null) return 'No messages yet';
    final msgType = event.content['msgtype'] as String?;
    if (msgType == 'm.image') return '📷 Photo';
    if (msgType == 'm.video') return '🎥 Video';
    if (msgType == 'm.audio') return '🎵 Audio';
    if (msgType == 'm.file') return '📎 File';
    return event.body.replaceAll('\n', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(matrixClientProvider);
    final networkState = ref.watch(networkHubProvider);

    return StreamBuilder(
      stream: client.onSync.stream,
      builder: (context, _) {
        final rooms = _getFilteredRooms(client, networkState);

        if (rooms.isEmpty) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: Text(
                'No messages yet.\nConnect a network to get started.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 16),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0.5,
            title: const Text('All Messages',
                style: TextStyle(
                    color: Colors.black87, fontWeight: FontWeight.bold)),
          ),
          body: ListView.separated(
            itemCount: rooms.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 76, color: Color(0xFFF2F2F7)),
            itemBuilder: (context, index) {
              final room = rooms[index];
              final networkId =
                  BridgeRoomClassifier.getNetworkForRoom(room, client: client);
              final networkMeta = networkId != null ? metaFor(networkId) : null;

              // FIXED: Uses matrix native notificationCount instead of .unread
              final hasUnread = room.notificationCount > 0;
              final String initial = room.displayname.isNotEmpty
                  ? room.displayname[0].toUpperCase()
                  : '?';
              final avatarUrl = room.avatar
                  ?.getThumbnail(client, width: 120, height: 120)
                  .toString();

              return InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ChatScreen(room: room)),
                  );
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                shape: BoxShape.circle),
                            clipBehavior: Clip.antiAlias,
                            child: avatarUrl != null
                                ? Image.network(
                                    avatarUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Center(
                                        child: Text(initial,
                                            style: const TextStyle(
                                                fontSize: 20,
                                                color: Colors.blue,
                                                fontWeight: FontWeight.w600))),
                                  )
                                : Center(
                                    child: Text(initial,
                                        style: const TextStyle(
                                            fontSize: 20,
                                            color: Colors.blue,
                                            fontWeight: FontWeight.w600))),
                          ),
                          if (networkMeta != null)
                            Positioned(
                              bottom: -2,
                              right: -2,
                              child: Container(
                                padding: const EdgeInsets.all(2.5),
                                decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle),
                                child: CircleAvatar(
                                  radius: 9,
                                  backgroundColor: networkMeta.brandColor,
                                  child: networkMeta.asset != null
                                      ? Image.asset(networkMeta.asset!,
                                          width: 10,
                                          height: 10,
                                          color: Colors.white)
                                      : Icon(networkMeta.icon,
                                          size: 10, color: Colors.white),
                                ),
                              ),
                            )
                        ],
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    room.displayname,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontWeight: hasUnread
                                            ? FontWeight.bold
                                            : FontWeight.w600,
                                        fontSize: 16.5,
                                        color: Colors.black87),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatTime(room.lastEvent?.originServerTs),
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: hasUnread
                                          ? Colors.blue
                                          : Colors.black54,
                                      fontWeight: hasUnread
                                          ? FontWeight.bold
                                          : FontWeight.normal),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _getPreviewText(room),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: hasUnread
                                            ? Colors.black87
                                            : Colors.black54,
                                        fontWeight: hasUnread
                                            ? FontWeight.w500
                                            : FontWeight.normal,
                                        fontSize: 14.5),
                                  ),
                                ),
                                if (hasUnread) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                        color: Colors.blue,
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    child: Text(
                                      room.notificationCount > 99
                                          ? '99+'
                                          : room.notificationCount.toString(),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

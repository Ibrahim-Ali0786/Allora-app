// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import '../providers/network_provider.dart';
import './bridge/bridge_room_classifier.dart';
import './networks/network_meta.dart';
import './widgets/sliding_drawer.dart'; // Import slide drawer
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
            .contains(metaFor(networkId).botAlias)) return false;
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

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(matrixClientProvider);
    final networkState = ref.watch(networkHubProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      drawer: const EnterpriseSlidingDrawer(), // Integrated sliding setup
      appBar: AppBar(
        title: const Text('All Messages',
            style: TextStyle(
                color: Color(0xFF1C1C1E), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Color(0xFF1C1C1E)),
      ),
      body: StreamBuilder(
        stream: client.onSync.stream,
        builder: (context, _) {
          final rooms = _getFilteredRooms(client, networkState);

          if (rooms.isEmpty) {
            return const Center(
              child: Text(
                'No messages yet.\nOpen the menu to connect a network.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 16),
              ),
            );
          }

          return ListView.separated(
            itemCount: rooms.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 70),
            itemBuilder: (context, index) {
              final room = rooms[index];
              final networkId =
                  BridgeRoomClassifier.getNetworkForRoom(room, client: client);
              final networkMeta = networkId != null ? metaFor(networkId) : null;

              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.blue.withOpacity(0.1),
                      backgroundImage: room.avatar != null
                          ? NetworkImage(room.avatar!
                              .getThumbnail(client, width: 100, height: 100)
                              .toString())
                          : null,
                      child: room.avatar == null
                          ? Text(room.displayname[0].toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 20, color: Colors.blue))
                          : null,
                    ),
                    if (networkMeta != null)
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                              color: Colors.white, shape: BoxShape.circle),
                          child: CircleAvatar(
                            radius: 8,
                            backgroundColor: networkMeta.brandColor,
                            child: networkMeta.asset != null
                                ? Image.asset(networkMeta.asset!,
                                    width: 10, height: 10, color: Colors.white)
                                : Icon(networkMeta.icon,
                                    size: 10, color: Colors.white),
                          ),
                        ),
                      )
                  ],
                ),
                title: Text(room.displayname,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 16)),
                subtitle: Text(
                  room.lastEvent?.content['body'] ?? 'Image/Media',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54),
                ),
                trailing: room.unread > 0
                    ? Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                            color: Color(0xFF007AFF), shape: BoxShape.circle),
                        child: Text(room.unread.toString(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      )
                    : null,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ChatScreen(room: room)),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

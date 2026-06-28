import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import '../../providers/network_provider.dart';
import '../connect_networks_screen.dart';

class EnterpriseSlidingDrawer extends ConsumerWidget {
  const EnterpriseSlidingDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(matrixClientProvider);
    final networkState = ref.watch(networkHubProvider);

    final connectedCount = networkState.networks
        .where((n) => n.status == NetworkStatus.connected)
        .length;
    final totalCount = networkState.networks
        .where((n) => n.status != NetworkStatus.comingSoon)
        .length;

    return Drawer(
      backgroundColor: const Color(0xFFF5F5F7), // Matching _T.canvas
      child: Column(
        children: [
          _buildProfileHeader(client),
          _buildSyncOverview(
              connectedCount, totalCount, networkState.isWipePending),
          const Divider(height: 1, color: Color(0xFFE5E5EA)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline,
                      color: Color(0xFF1C1C1E)),
                  title: const Text('All Messages',
                      style: TextStyle(fontWeight: FontWeight.w500)),
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${client.rooms.where((r) => r.unread > 0).length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  onTap: () => Navigator.pop(context),
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_sync_outlined,
                      color: Color(0xFF1C1C1E)),
                  title: const Text('Connect Networks',
                      style: TextStyle(fontWeight: FontWeight.w500)),
                  trailing: const Icon(Icons.chevron_right,
                      size: 16, color: Color(0xFFADAFB8)),
                  onTap: () {
                    Navigator.pop(context); // Close Drawer
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ConnectNetworksScreen(client: client),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          _buildFooterVersion(),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(Client client) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
      color: Colors.white,
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFFEFF6FF),
            child: Text(
              (client.userID ?? 'U').substring(1, 2).toUpperCase(),
              style: const TextStyle(
                  color: Color(0xFF007AFF),
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.userID?.split(':').first.replaceAll('@', '') ??
                      'Active User',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1C1C1E)),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  client.homeserver?.host ?? 'allorachat.app',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF6B6D78)),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncOverview(int connected, int total, bool isWiping) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: const Color(0xFFEFF6FF),
      child: Row(
        children: [
          Icon(
            isWiping ? Icons.sync : Icons.check_circle_outline,
            size: 16,
            color: const Color(0xFF007AFF),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isWiping
                  ? 'Clearing accounts...'
                  : '$connected / $total Infrastructure Relays Active',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF007AFF)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterVersion() {
    return Container(
      padding: const EdgeInsets.all(16),
      alignment: Alignment.centerLeft,
      child: const Text(
        'Allora Enterprise v2.0.0',
        style: TextStyle(
            fontSize: 11, color: Color(0xFFADAFB8), letterSpacing: 0.3),
      ),
    );
  }
}

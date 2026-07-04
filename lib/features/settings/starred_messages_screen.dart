import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/allora_avatar.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/utils/chat_time.dart';
import '../../data/settings/app_settings.dart';
import '../../providers/network_provider.dart';
import '../chat/chat_screen.dart';

class StarredMessagesScreen extends ConsumerWidget {
  const StarredMessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.allora;
    final starred = ref.watch(settingsProvider.select((s) => s.starred));
    final client = ref.watch(matrixClientProvider);

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(title: const Text('Starred messages')),
      body: starred.isEmpty
          ? const EmptyState(
              icon: Icons.star_rounded,
              title: 'Nothing starred yet',
              message:
                  'Hold any message and tap Star to keep it here for quick access.',
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: starred.length,
              itemBuilder: (context, i) {
                final s = starred[i];
                return Dismissible(
                  key: ValueKey(s.eventId),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) =>
                      ref.read(settingsProvider.notifier).toggleStarred(s),
                  background: Container(
                    color: c.danger,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: const Icon(Icons.star_outline_rounded,
                        color: Colors.white),
                  ),
                  child: ListTile(
                    leading: AlloraAvatar(
                        name: s.senderName, size: 42, showNetworkBadge: false),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(s.senderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        Text(
                          ChatTime.listStamp(
                              DateTime.fromMillisecondsSinceEpoch(s.tsMs)),
                          style: TextStyle(
                              fontSize: 11.5, color: c.textTertiary),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.preview,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        Text(s.roomName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11.5, color: c.accent)),
                      ],
                    ),
                    onTap: () {
                      final room = client.getRoomById(s.roomId);
                      if (room == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('This chat is no longer available')));
                        return;
                      }
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ChatScreen(room: room)));
                    },
                  ),
                );
              },
            ),
    );
  }
}

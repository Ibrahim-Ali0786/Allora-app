import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/settings/app_settings.dart';
import '../chat/chat_screen.dart';
import 'chat_list_providers.dart';
import 'widgets/chat_tile.dart';

class ArchivedChatsScreen extends ConsumerWidget {
  const ArchivedChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.allora;
    final archived = ref.watch(archivedChatsProvider);

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(title: const Text('Archived')),
      body: archived.isEmpty
          ? const EmptyState(
              icon: Icons.archive_rounded,
              title: 'Nothing archived',
              message: 'Swipe a chat left in your inbox to tuck it away here.',
            )
          : ListView.builder(
              itemCount: archived.length,
              itemBuilder: (context, i) {
                final entry = archived[i];
                return ChatTile(
                  entry: entry,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ChatScreen(room: entry.room))),
                  onLongPress: () {
                    ref
                        .read(settingsProvider.notifier)
                        .setArchived(entry.room.id, false);
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${entry.title} unarchived')));
                  },
                );
              },
            ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/chat_time.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/services/scheduled_message_service.dart';

class ScheduledMessagesScreen extends StatelessWidget {
  const ScheduledMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(title: const Text('Scheduled messages')),
      body: ValueListenableBuilder<List<ScheduledMessage>>(
        valueListenable: ScheduledMessageService.queue,
        builder: (context, queue, _) {
          if (queue.isEmpty) {
            return const EmptyState(
              icon: Icons.schedule_send_rounded,
              title: 'Nothing scheduled',
              message:
                  'Hold the send button in any chat to schedule a message '
                  'for later.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: queue.length,
            itemBuilder: (context, i) {
              final m = queue[i];
              final sendAt = DateTime.fromMillisecondsSinceEpoch(m.sendAtMs);
              return ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.schedule_send_rounded,
                      color: c.accent, size: 20),
                ),
                title: Text(m.roomName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text(
                      '${ChatTime.dayHeader(sendAt)} · ${ChatTime.hourMinute(sendAt)}',
                      style: TextStyle(fontSize: 11.5, color: c.accent),
                    ),
                  ],
                ),
                trailing: IconButton(
                  tooltip: 'Cancel',
                  icon: Icon(Icons.close_rounded, color: c.textSecondary),
                  onPressed: () => ScheduledMessageService.cancel(m.id),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

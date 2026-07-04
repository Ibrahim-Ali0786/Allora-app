// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/allora_avatar.dart';
import '../../chat_list/chat_list_providers.dart';

/// Pick a destination chat and forward [event]'s content to it.
void showForwardSheet(BuildContext context, WidgetRef ref,
    {required Event event}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.6,
      child: _ForwardSheet(event: event),
    ),
  );
}

class _ForwardSheet extends ConsumerStatefulWidget {
  final Event event;
  const _ForwardSheet({required this.event});

  @override
  ConsumerState<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends ConsumerState<_ForwardSheet> {
  String _query = '';
  String? _sendingTo;

  Future<void> _forward(ChatEntry entry) async {
    if (_sendingTo != null) return;
    setState(() => _sendingTo = entry.room.id);
    try {
      // Re-send the original content; strip relations so the copy is clean.
      final content = Map<String, dynamic>.from(widget.event.content);
      content.remove('m.relates_to');
      await entry.room.sendEvent(content);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Forwarded to ${entry.title}')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _sendingTo = null);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Forwarding failed. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    final data = ref.watch(chatListProvider);
    final all = [...data.pinned, ...data.chats]
        .where((e) =>
            _query.isEmpty ||
            e.title.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(
            children: [
              Icon(Icons.forward_rounded, color: c.accent),
              const SizedBox(width: 10),
              Text('Forward to…',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: c.text)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Search chats…',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.builder(
            itemCount: all.length,
            itemBuilder: (context, i) {
              final entry = all[i];
              final sending = _sendingTo == entry.room.id;
              return ListTile(
                leading: AlloraAvatar(
                  name: entry.title,
                  mxcUri: entry.room.avatar,
                  client: entry.room.client,
                  size: 42,
                  network: entry.network,
                ),
                title: Text(entry.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.send_rounded,
                        size: 18, color: c.textTertiary),
                onTap: () => _forward(entry),
              );
            },
          ),
        ),
      ],
    );
  }
}

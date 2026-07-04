import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/services/disappearing_message_service.dart';
import '../../../data/settings/app_settings.dart';

/// Per-chat disappearing message timer picker.
void showDisappearingSheet(BuildContext context, WidgetRef ref, Room room) {
  final current =
      ref.read(settingsProvider).disappearingSeconds[room.id] ?? 0;

  showModalBottomSheet(
    context: context,
    builder: (ctx) {
      final c = ctx.allora;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 6),
              child: Row(
                children: [
                  Icon(Icons.timer_outlined, color: c.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Disappearing messages',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: c.text)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
              child: Text(
                'Messages you send in this chat are automatically deleted '
                'after the selected time. Where the server allows it, Allora '
                'also asks it to purge history for everyone.',
                style: TextStyle(
                    fontSize: 13, color: c.textSecondary, height: 1.45),
              ),
            ),
            for (final entry in DisappearingMessageService.presets.entries)
              RadioListTile<int>(
                value: entry.key,
                groupValue: current,
                activeColor: c.accent,
                title: Text(entry.value,
                    style: TextStyle(fontSize: 15, color: c.text)),
                onChanged: (v) async {
                  Navigator.pop(ctx);
                  if (v == null) return;
                  await DisappearingMessageService.setTimer(room, v);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(v == 0
                          ? 'Disappearing messages off'
                          : 'Messages disappear after ${DisappearingMessageService.labelFor(v)}')));
                },
              ),
            ListTile(
              leading: Icon(Icons.tune_rounded, color: c.textSecondary),
              title: Text('Custom…',
                  style: TextStyle(fontSize: 15, color: c.text)),
              onTap: () async {
                Navigator.pop(ctx);
                final hours = await _askCustomHours(context);
                if (hours == null || hours <= 0) return;
                await DisappearingMessageService.setTimer(room, hours * 3600);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          'Messages disappear after ${DisappearingMessageService.labelFor(hours * 3600)}')));
                }
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      );
    },
  );
}

Future<int?> _askCustomHours(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Custom timer'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Hours (e.g. 48)',
          suffixText: 'hours',
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx, int.tryParse(controller.text.trim())),
          child: const Text('Set'),
        ),
      ],
    ),
  );
}

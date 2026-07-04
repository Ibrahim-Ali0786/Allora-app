import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/chat_time.dart';

/// Delivery details for a single message.
void showMessageInfoSheet(BuildContext context, Event event) {
  showModalBottomSheet(
    context: context,
    builder: (ctx) {
      final c = ctx.allora;
      final ts = event.originServerTs;
      String statusLabel;
      if (event.status == EventStatus.error) {
        statusLabel = 'Failed to send';
      } else if (event.status == EventStatus.sending) {
        statusLabel = 'Sending…';
      } else if (event.status == EventStatus.sent) {
        statusLabel = 'Sent';
      } else {
        statusLabel = 'Delivered to server';
      }

      Widget row(String label, String value, {bool mono = false}) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 86,
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: c.textTertiary)),
                ),
                Expanded(
                  child: Text(value,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: c.text,
                        fontFamily: mono ? 'monospace' : null,
                      )),
                ),
              ],
            ),
          );

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 10),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: c.accent),
                  const SizedBox(width: 10),
                  Text('Message info',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: c.text)),
                ],
              ),
            ),
            row('From',
                event.senderFromMemoryOrFallback.calcDisplayname()),
            row('Sent', '${ChatTime.dayHeader(ts)} · ${ChatTime.hourMinute(ts)}'),
            row('Status', statusLabel),
            row('Type', event.content['msgtype']?.toString() ?? event.type),
            row('Event ID', event.eventId, mono: true),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: event.eventId));
                Navigator.pop(ctx);
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy event ID'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

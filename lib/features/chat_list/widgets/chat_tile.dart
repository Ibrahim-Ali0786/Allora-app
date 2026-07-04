import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/chat_time.dart';
import '../../../core/widgets/allora_avatar.dart';
import '../chat_list_providers.dart';

/// One conversation row. Wrapped in a [RepaintBoundary] by the list so a
/// badge animating in one row never repaints its neighbours.
class ChatTile extends StatelessWidget {
  final ChatEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const ChatTile({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    final room = entry.room;
    final preview = previewFor(entry.lastEvent,
        isGroup: entry.isGroup, myUserId: room.client.userID);
    final hasStamp = entry.lastEvent != null;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            Hero(
              tag: 'avatar_${room.id}',
              child: AlloraAvatar(
                name: entry.title,
                mxcUri: room.avatar,
                client: room.client,
                size: 54,
                network: entry.network,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            height: 1.25,
                            letterSpacing: -0.15,
                            fontWeight:
                                entry.isUnread ? FontWeight.w700 : FontWeight.w600,
                            color: c.text,
                          ),
                        ),
                      ),
                      for (final label in entry.labels.take(3))
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: label.color, shape: BoxShape.circle),
                          ),
                        ),
                      if (entry.muted)
                        Padding(
                          padding: const EdgeInsets.only(left: 5),
                          child: Icon(Icons.notifications_off_rounded,
                              size: 14, color: c.textTertiary),
                        ),
                      if (hasStamp)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            ChatTime.listStamp(entry.lastActivity),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: entry.isUnread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color:
                                  entry.isUnread ? c.accent : c.textTertiary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: entry.typing
                            ? _TypingPreview(color: c.accent)
                            : Row(
                                children: [
                                  if (_glyphIcon(preview.glyph) != null) ...[
                                    Icon(_glyphIcon(preview.glyph),
                                        size: 15,
                                        color: entry.isUnread
                                            ? c.textSecondary
                                            : c.textTertiary),
                                    const SizedBox(width: 4),
                                  ],
                                  Expanded(
                                    child: Text(
                                      preview.text,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        height: 1.3,
                                        fontStyle:
                                            preview.glyph == PreviewGlyph.deleted
                                                ? FontStyle.italic
                                                : FontStyle.normal,
                                        fontWeight: entry.isUnread
                                            ? FontWeight.w500
                                            : FontWeight.w400,
                                        color: entry.isUnread
                                            ? c.textSecondary
                                            : c.textTertiary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(width: 8),
                      if (entry.pinned && !entry.isUnread)
                        Icon(Icons.push_pin_rounded,
                            size: 15, color: c.textTertiary),
                      if (entry.unreadCount > 0)
                        _UnreadBadge(count: entry.unreadCount, muted: entry.muted)
                      else if (entry.markedUnread)
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: c.accent, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData? _glyphIcon(PreviewGlyph glyph) {
    switch (glyph) {
      case PreviewGlyph.photo:
        return Icons.photo_camera_rounded;
      case PreviewGlyph.video:
        return Icons.videocam_rounded;
      case PreviewGlyph.voice:
        return Icons.mic_rounded;
      case PreviewGlyph.file:
        return Icons.description_rounded;
      case PreviewGlyph.location:
        return Icons.location_on_rounded;
      case PreviewGlyph.sticker:
        return Icons.emoji_emotions_rounded;
      case PreviewGlyph.deleted:
        return Icons.block_rounded;
      case PreviewGlyph.none:
        return null;
    }
  }
}

/// Unread pill that pops (scale-overshoot) whenever the count changes.
class _UnreadBadge extends StatelessWidget {
  final int count;
  final bool muted;
  const _UnreadBadge({required this.count, required this.muted});

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    return TweenAnimationBuilder<double>(
      key: ValueKey(count),
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.elasticOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        constraints: const BoxConstraints(minWidth: 21),
        height: 21,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: muted ? c.textTertiary : c.accent,
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: Text(
          count > 99 ? '99+' : '$count',
          style: TextStyle(
            color: c.onAccent,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// "typing" with three bouncing dots, shown in the preview line.
class _TypingPreview extends StatefulWidget {
  final Color color;
  const _TypingPreview({required this.color});

  @override
  State<_TypingPreview> createState() => _TypingPreviewState();
}

class _TypingPreviewState extends State<_TypingPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'typing',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: widget.color,
          ),
        ),
        const SizedBox(width: 3),
        AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            return Row(
              children: List.generate(3, (i) {
                final t = (_ctrl.value * 3 - i).clamp(0.0, 1.0);
                final bounce = (t < 0.5 ? t : 1 - t) * 2;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Transform.translate(
                    offset: Offset(0, -2.5 * bounce),
                    child: Container(
                      width: 3.5,
                      height: 3.5,
                      decoration: BoxDecoration(
                        color: widget.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }
}

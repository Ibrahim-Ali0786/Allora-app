// ignore_for_file: deprecated_member_use
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/matrix_media.dart';
import 'message_bubble.dart' show stripReplyFallback;

class MessageMenuAction {
  final IconData icon;
  final String label;
  final bool destructive;
  final VoidCallback onTap;

  const MessageMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });
}

const kQuickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// Beeper-style hold menu: the screen blurs, a floating replica of the
/// message appears at its original position, a reaction bar springs in
/// above it and an action card below (auto-flipping when near an edge).
Future<void> showMessageContextMenu({
  required BuildContext context,
  required Event event,
  required Rect bubbleRect,
  required bool isMe,
  required void Function(String emoji) onReact,
  required Future<void> Function() onMoreReactions,
  required List<MessageMenuAction> actions,
}) {
  HapticFeedback.mediumImpact();
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => _ContextMenuOverlay(
        event: event,
        bubbleRect: bubbleRect,
        isMe: isMe,
        onReact: onReact,
        onMoreReactions: onMoreReactions,
        actions: actions,
      ),
      transitionsBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        return FadeTransition(opacity: curved, child: child);
      },
    ),
  );
}

class _ContextMenuOverlay extends StatelessWidget {
  final Event event;
  final Rect bubbleRect;
  final bool isMe;
  final void Function(String emoji) onReact;
  final Future<void> Function() onMoreReactions;
  final List<MessageMenuAction> actions;

  const _ContextMenuOverlay({
    required this.event,
    required this.bubbleRect,
    required this.isMe,
    required this.onReact,
    required this.onMoreReactions,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    final screen = MediaQuery.of(context).size;
    final topSafe = MediaQuery.of(context).padding.top;

    const reactionBarHeight = 52.0;
    final menuHeight = (actions.length * 46.0) + 12;
    final previewMaxHeight = screen.height * 0.32;
    final previewHeight =
        bubbleRect.height.clamp(36.0, previewMaxHeight);

    // Stack the three blocks vertically around the original bubble position,
    // clamped to stay fully on screen.
    final totalHeight = reactionBarHeight + 8 + previewHeight + 8 + menuHeight;
    var top = bubbleRect.top - reactionBarHeight - 8;
    final lowerBound = topSafe + 12;
    final upperBound = (screen.height - totalHeight - 24) < lowerBound
        ? lowerBound
        : (screen.height - totalHeight - 24);
    top = top.clamp(lowerBound, upperBound);

    final horizontalPadding = 14.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.pop(context),
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                color: (Theme.of(context).brightness == Brightness.dark
                        ? Colors.black
                        : Colors.white)
                    .withValues(alpha: 0.35),
              ),
            ),
          ),
          Positioned(
            top: top,
            left: horizontalPadding,
            right: horizontalPadding,
            child: GestureDetector(
              onTap: () {}, // swallow taps inside the menu column
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _springIn(
                    delay: 0,
                    child: _ReactionBar(
                      onReact: (e) {
                        Navigator.pop(context);
                        onReact(e);
                      },
                      onMore: () async {
                        Navigator.pop(context);
                        await onMoreReactions();
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: previewMaxHeight,
                      maxWidth: screen.width * 0.8,
                    ),
                    child: _BubblePreview(event: event, isMe: isMe),
                  ),
                  const SizedBox(height: 8),
                  _springIn(
                    delay: 40,
                    child: Container(
                      width: 248,
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: c.outline),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      clipBehavior: Clip.antiAlias,
                      child: Material(
                        type: MaterialType.transparency,
                        child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < actions.length; i++) ...[
                              if (i > 0 &&
                                  actions[i].destructive &&
                                  !actions[i - 1].destructive)
                                Divider(color: c.outline, height: 6),
                              _ActionRow(
                                action: actions[i],
                                onDone: () => Navigator.pop(context),
                              ),
                            ],
                          ],
                        ),
                      ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _springIn({required int delay, required Widget child}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + delay),
      curve: Curves.easeOutBack,
      builder: (context, t, c2) => Transform.scale(
        scale: 0.7 + 0.3 * t,
        alignment: isMe ? Alignment.topRight : Alignment.topLeft,
        child: Opacity(opacity: t.clamp(0.0, 1.0), child: c2),
      ),
      child: child,
    );
  }
}

class _ReactionBar extends StatelessWidget {
  final void Function(String) onReact;
  final VoidCallback onMore;

  const _ReactionBar({required this.onReact, required this.onMore});

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.outline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final emoji in kQuickReactions)
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                HapticFeedback.lightImpact();
                onReact(emoji);
              },
              child: Padding(
                padding: const EdgeInsets.all(7),
                child: Text(emoji, style: const TextStyle(fontSize: 22)),
              ),
            ),
          InkWell(
            customBorder: const CircleBorder(),
            onTap: onMore,
            child: Container(
              margin: const EdgeInsets.only(left: 2),
              padding: const EdgeInsets.all(6),
              decoration:
                  BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
              child: Icon(Icons.add_rounded, size: 20, color: c.textSecondary),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final MessageMenuAction action;
  final VoidCallback onDone;

  const _ActionRow({required this.action, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    final color = action.destructive ? c.danger : c.text;
    return InkWell(
      onTap: () {
        onDone();
        action.onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Text(
                action.label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
            Icon(action.icon,
                size: 19,
                color: action.destructive ? c.danger : c.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Static, simplified replica of the held message shown inside the overlay.
class _BubblePreview extends StatelessWidget {
  final Event event;
  final bool isMe;

  const _BubblePreview({required this.event, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    final msgtype = event.content['msgtype'] as String? ?? 'm.text';

    Widget child;
    if (event.redacted) {
      child = Text('Message deleted',
          style: TextStyle(
              fontStyle: FontStyle.italic,
              color: isMe ? c.onAccent : c.textSecondary));
    } else if (msgtype == 'm.image' || event.type == EventTypes.Sticker) {
      final source = MatrixMedia.thumbnail(
          event.room.client, MatrixMedia.mxcOf(event),
          width: 600, height: 600);
      child = source == null
          ? Icon(Icons.image_rounded, color: isMe ? c.onAccent : c.textTertiary)
          : ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(source.url,
                  headers: source.headers, fit: BoxFit.cover, cacheWidth: 600),
            );
    } else if (msgtype == 'm.audio') {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_rounded, size: 18, color: isMe ? c.onAccent : c.text),
          const SizedBox(width: 6),
          Text('Voice message',
              style: TextStyle(color: isMe ? c.onAccent : c.text)),
        ],
      );
    } else {
      child = Text(
        stripReplyFallback(event.body),
        maxLines: 10,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15,
          height: 1.35,
          color: isMe ? c.onAccent : c.text,
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: isMe ? null : c.surface,
          gradient: isMe
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [c.bubbleMine, c.bubbleMineDeep])
              : null,
          borderRadius: BorderRadius.circular(18),
          border: isMe ? null : Border.all(color: c.outline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

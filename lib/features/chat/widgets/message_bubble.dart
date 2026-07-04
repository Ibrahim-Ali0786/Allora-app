// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/chat_time.dart';
import '../../../core/widgets/allora_avatar.dart';
import '../../../core/utils/matrix_media.dart';
import '../../../core/widgets/link_text.dart';
import 'image_viewer.dart';
import 'video_player_screen.dart';

/// Strips the legacy `> quoted` fallback block from reply bodies.
String stripReplyFallback(String body) {
  if (!body.startsWith('> ')) return body;
  final lines = body.split('\n');
  var i = 0;
  while (i < lines.length && lines[i].startsWith('> ')) {
    i++;
  }
  while (i < lines.length && lines[i].trim().isEmpty) {
    i++;
  }
  return lines.sublist(i).join('\n');
}

String? replyToEventId(Event event) {
  final relates = event.content['m.relates_to'];
  if (relates is Map) {
    final inReply = relates['m.in_reply_to'];
    if (inReply is Map) return inReply['event_id']?.toString();
  }
  return null;
}

/// One message row: avatar (groups), bubble with content + inline footer,
/// reaction chips, swipe-to-reply, long-press menu hook, selection state.
class MessageBubble extends StatefulWidget {
  final Event event; // display event (edits already applied)
  final Timeline timeline;
  final Event? older; // previous message in time
  final Event? newer; // next message in time
  final bool selectionMode;
  final bool selected;
  final bool highlighted;
  final double fontScale;
  final Event? Function(String eventId) resolveEvent;
  final void Function(Event event, Rect bubbleRect) onLongPress;
  final void Function(Event event) onSwipeReply;
  final VoidCallback onTap;
  final void Function(String eventId) onJumpTo;
  final Future<void> Function(Event event, String key) onToggleReaction;

  const MessageBubble({
    super.key,
    required this.event,
    required this.timeline,
    required this.older,
    required this.newer,
    required this.selectionMode,
    required this.selected,
    required this.highlighted,
    required this.fontScale,
    required this.resolveEvent,
    required this.onLongPress,
    required this.onSwipeReply,
    required this.onTap,
    required this.onJumpTo,
    required this.onToggleReaction,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  final _bubbleKey = GlobalKey();
  double _dragX = 0;
  bool _pressed = false;

  static const _groupWindow = Duration(minutes: 3);

  Event get event => widget.event;
  Room get room => event.room;
  bool get isMe => event.senderId == room.client.userID;

  bool _sameAuthor(Event? other) {
    if (other == null) return false;
    if (other.senderId != event.senderId) return false;
    if (other.type != EventTypes.Message &&
        other.type != EventTypes.Encrypted &&
        other.type != EventTypes.Sticker) {
      return false;
    }
    return true;
  }

  bool get _isFirstInGroup {
    final older = widget.older;
    if (!_sameAuthor(older)) return true;
    if (!ChatTime.sameDay(older!.originServerTs, event.originServerTs)) {
      return true;
    }
    return event.originServerTs.difference(older.originServerTs) >
        _groupWindow;
  }

  bool get _isLastInGroup {
    final newer = widget.newer;
    if (!_sameAuthor(newer)) return true;
    if (!ChatTime.sameDay(newer!.originServerTs, event.originServerTs)) {
      return true;
    }
    return newer.originServerTs.difference(event.originServerTs) >
        _groupWindow;
  }

  void _handleLongPress() {
    HapticFeedback.mediumImpact();
    final box = _bubbleKey.currentContext?.findRenderObject() as RenderBox?;
    final rect = box == null
        ? Rect.zero
        : box.localToGlobal(Offset.zero) & box.size;
    widget.onLongPress(event, rect);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    final isGroupChat = !room.isDirectChat;
    final showAvatar = !isMe && isGroupChat;
    final showName = showAvatar && _isFirstInGroup;

    final bubble = _buildBubble(context);

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment:
          isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (widget.selectionMode)
          Padding(
            padding: const EdgeInsets.only(right: 6, bottom: 6),
            child: AnimatedScale(
              scale: 1,
              duration: const Duration(milliseconds: 150),
              child: Icon(
                widget.selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 21,
                color: widget.selected ? c.accent : c.textTertiary,
              ),
            ),
          ),
        if (showAvatar)
          Padding(
            padding: const EdgeInsets.only(right: 7, bottom: 2),
            child: _isLastInGroup
                ? AlloraAvatar(
                    name: event.senderFromMemoryOrFallback.calcDisplayname(),
                    mxcUri: event.senderFromMemoryOrFallback.avatarUrl,
                    client: room.client,
                    size: 28,
                    showNetworkBadge: false,
                  )
                : const SizedBox(width: 28),
          ),
        Flexible(
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (showName)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 2),
                  child: Text(
                    event.senderFromMemoryOrFallback.calcDisplayname(),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: colorForId(event.senderId,
                          dark:
                              Theme.of(context).brightness == Brightness.dark),
                    ),
                  ),
                ),
              bubble,
              _ReactionsRow(
                event: event,
                timeline: widget.timeline,
                isMe: isMe,
                onToggle: (key) => widget.onToggleReaction(event, key),
              ),
            ],
          ),
        ),
      ],
    );

    // Swipe-to-reply: light horizontal drag with a spring back.
    return Padding(
      padding: EdgeInsets.only(
        left: 10,
        right: 10,
        top: _isFirstInGroup ? 8 : 1.5,
        bottom: _isLastInGroup ? 2 : 0,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onHorizontalDragUpdate: widget.selectionMode
            ? null
            : (d) => setState(() {
                  _dragX = (_dragX + d.delta.dx).clamp(isMe ? -72.0 : 0.0,
                      isMe ? 0.0 : 72.0);
                }),
        onHorizontalDragEnd: widget.selectionMode
            ? null
            : (_) {
                if (_dragX.abs() > 44) {
                  HapticFeedback.lightImpact();
                  widget.onSwipeReply(event);
                }
                setState(() => _dragX = 0);
              },
        child: Stack(
          children: [
            if (_dragX.abs() > 6)
              Positioned.fill(
                child: Align(
                  alignment:
                      isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Opacity(
                      opacity: (_dragX.abs() / 60).clamp(0.0, 1.0),
                      child: Icon(Icons.reply_rounded,
                          size: 20, color: c.textSecondary),
                    ),
                  ),
                ),
              ),
            AnimatedContainer(
              duration: _dragX == 0
                  ? const Duration(milliseconds: 220)
                  : Duration.zero,
              curve: Curves.easeOutBack,
              transform: Matrix4.translationValues(_dragX, 0, 0),
              child: row,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(BuildContext context) {
    final c = context.allora;
    final maxWidth = MediaQuery.of(context).size.width * 0.78;

    final BorderRadius radius;
    const r = Radius.circular(19);
    const rs = Radius.circular(6);
    if (isMe) {
      radius = BorderRadius.only(
        topLeft: r,
        bottomLeft: r,
        topRight: _isFirstInGroup ? r : rs,
        bottomRight: rs, // WhatsApp-style tail corner on own bubbles
      );
    } else {
      radius = BorderRadius.only(
        topRight: r,
        bottomRight: r,
        topLeft: _isFirstInGroup ? r : rs,
        bottomLeft: rs,
      );
    }

    final isMedia = _isImage;
    final bg = event.redacted
        ? c.surfaceAlt
        : isMe
            ? null
            : c.surface;

    return GestureDetector(
      onTap: widget.selectionMode ? widget.onTap : null,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onLongPress: widget.selectionMode ? widget.onTap : _handleLongPress,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          key: _bubbleKey,
          duration: const Duration(milliseconds: 300),
          constraints: BoxConstraints(maxWidth: maxWidth),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: widget.highlighted
                ? c.accent.withValues(alpha: 0.25)
                : widget.selected
                    ? c.accent.withValues(alpha: 0.18)
                    : bg,
            gradient: (isMe && !event.redacted && !widget.selected &&
                    !widget.highlighted)
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [c.bubbleMine, c.bubbleMineDeep],
                  )
                : null,
            borderRadius: radius,
            border: !isMe && !event.redacted
                ? Border.all(color: c.outline, width: 0.8)
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          padding: isMedia
              ? const EdgeInsets.all(3.5)
              : const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (replyToEventId(event) != null && !event.redacted)
                _ReplyPreview(
                  replyId: replyToEventId(event)!,
                  resolveEvent: widget.resolveEvent,
                  isMine: isMe,
                  onJumpTo: widget.onJumpTo,
                  inMediaBubble: isMedia,
                ),
              _content(context),
              Padding(
                padding: isMedia
                    ? const EdgeInsets.fromLTRB(8, 3, 6, 3)
                    : EdgeInsets.zero,
                child: _footer(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Content variants ──────────────────────────────────────────────────────

  bool get _isImage =>
      !event.redacted &&
      (event.content['msgtype'] == 'm.image' ||
          event.type == EventTypes.Sticker) &&
      event.content['url'] is String;

  Widget _content(BuildContext context) {
    final c = context.allora;

    if (event.redacted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block_rounded, size: 15, color: c.textTertiary),
          const SizedBox(width: 6),
          Text('Message deleted',
              style: TextStyle(
                  fontSize: 14 * widget.fontScale,
                  fontStyle: FontStyle.italic,
                  color: c.textTertiary)),
        ],
      );
    }

    if (event.type == EventTypes.Encrypted) {
      return _mutedLine(context, Icons.lock_outline_rounded,
          'Encrypted message — unable to decrypt');
    }

    final msgtype = event.content['msgtype'] as String? ?? 'm.text';
    switch (msgtype) {
      case 'm.image':
        return _imageContent(context);
      case 'm.audio':
        return _audioContent(context);
      case 'm.video':
        return _videoContent(context);
      case 'm.file':
        return _fileLikeContent(context,
            icon: Icons.description_rounded, label: 'File');
      case 'm.location':
        return _fileLikeContent(context,
            icon: Icons.location_on_rounded, label: 'Location');
      default:
        if (event.type == EventTypes.Sticker) return _imageContent(context);
        return _textContent(context);
    }
  }

  Widget _mutedLine(BuildContext context, IconData icon, String text) {
    final c = context.allora;
    final color = isMe ? c.onAccent.withValues(alpha: 0.8) : c.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text,
              style: TextStyle(
                  fontSize: 13.5 * widget.fontScale,
                  fontStyle: FontStyle.italic,
                  color: color)),
        ),
      ],
    );
  }

  Widget _textContent(BuildContext context) {
    final c = context.allora;
    final body = stripReplyFallback(event.body);
    final emojiOnly = _isEmojiOnly(body);
    return LinkText(
      text: body,
      style: TextStyle(
        fontSize: (emojiOnly ? 34 : 15.5) * widget.fontScale,
        height: 1.35,
        letterSpacing: -0.1,
        color: isMe ? c.onAccent : c.text,
      ),
      linkColor: isMe ? c.onAccent : c.accent,
    );
  }

  static final _emojiOnlyPattern = RegExp(
      r'^[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}\s]+$',
      unicode: true);

  static bool _isEmojiOnly(String s) {
    final t = s.trim();
    return t.isNotEmpty && t.length <= 12 && _emojiOnlyPattern.hasMatch(t);
  }

  Widget _imageContent(BuildContext context) {
    final c = context.allora;
    final mxc = event.content['url'] as String?;
    final info = event.content['info'];
    double aspect = 4 / 3;
    if (info is Map) {
      final w = (info['w'] as num?)?.toDouble();
      final h = (info['h'] as num?)?.toDouble();
      if (w != null && h != null && w > 0 && h > 0) {
        aspect = (w / h).clamp(0.55, 2.4);
      }
    }

    final thumb =
        MatrixMedia.thumbnail(room.client, mxc, width: 800, height: 800);
    final full = MatrixMedia.download(room.client, mxc);

    final caption = stripReplyFallback(event.body);
    final showCaption = caption.isNotEmpty &&
        caption.toLowerCase() != 'image' &&
        !caption.toLowerCase().endsWith('.jpg') &&
        !caption.toLowerCase().endsWith('.jpeg') &&
        !caption.toLowerCase().endsWith('.png') &&
        !caption.toLowerCase().endsWith('.webp');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: widget.selectionMode
              ? widget.onTap
              : () {
                  if (full == null) return;
                  Navigator.of(context).push(ImageViewerScreen.route(
                    url: full.url,
                    headers: full.headers,
                    heroTag: 'img_${event.eventId}',
                    title: event.senderFromMemoryOrFallback.calcDisplayname(),
                  ));
                },
          child: Hero(
            tag: 'img_${event.eventId}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: AspectRatio(
                aspectRatio: aspect,
                child: thumb == null
                    ? Container(
                        color: c.surfaceAlt,
                        child: Icon(Icons.image_rounded,
                            color: c.textTertiary, size: 40),
                      )
                    : Image.network(
                        thumb.url,
                        headers: thumb.headers,
                        fit: BoxFit.cover,
                        cacheWidth: 800,
                        gaplessPlayback: true,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            color: c.surfaceAlt,
                            child: Center(
                              child: SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: c.textTertiary,
                                ),
                              ),
                            ),
                          );
                        },
                        errorBuilder: (_, __, ___) => Container(
                          color: c.surfaceAlt,
                          child: Icon(Icons.broken_image_rounded,
                              color: c.textTertiary, size: 36),
                        ),
                      ),
              ),
            ),
          ),
        ),
        if (showCaption)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
            child: Text(
              caption,
              style: TextStyle(
                fontSize: 14.5 * widget.fontScale,
                height: 1.35,
                color: isMe ? c.onAccent : c.text,
              ),
            ),
          ),
      ],
    );
  }

  Widget _audioContent(BuildContext context) {
    final c = context.allora;
    final fg = isMe ? c.onAccent : c.text;
    final info = event.content['info'];
    Duration? duration;
    if (info is Map && info['duration'] is num) {
      duration = Duration(milliseconds: (info['duration'] as num).toInt());
    }

    List<int> waveform = const [];
    final audioMeta = event.content['org.matrix.msc1767.audio'];
    if (audioMeta is Map && audioMeta['waveform'] is List) {
      waveform = (audioMeta['waveform'] as List)
          .whereType<num>()
          .map((n) => n.toInt())
          .toList();
    }
    if (waveform.isEmpty) {
      // Deterministic pseudo-waveform so the bubble still looks alive.
      var seed = event.eventId.hashCode;
      waveform = List.generate(28, (i) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        return 200 + seed % 800;
      });
    }

    return InkWell(
      onTap: () {
        final source = MatrixMedia.download(room.client, MatrixMedia.mxcOf(event));
        if (source == null) return;
        Navigator.of(context).push(VideoPlayerScreen.route(
          url: source.url,
          headers: source.headers,
          title: event.senderFromMemoryOrFallback.calcDisplayname(),
          isAudio: true,
        ));
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isMe ? c.onAccent.withValues(alpha: 0.22) : c.surfaceAlt,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.play_arrow_rounded, color: fg, size: 22),
          ),
          const SizedBox(width: 9),
          SizedBox(
            width: 120,
            height: 30,
            child: CustomPaint(
              painter: _WaveformPainter(
                waveform: waveform,
                color: fg.withValues(alpha: 0.85),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Text(
            duration != null ? ChatTime.duration(duration) : 'Voice',
            style: TextStyle(
              fontSize: 12.5 * widget.fontScale,
              fontWeight: FontWeight.w600,
              color: fg.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _videoContent(BuildContext context) {
    final c = context.allora;
    final info = event.content['info'];
    double aspect = 16 / 9;
    Duration? duration;
    String? thumbMxc;
    if (info is Map) {
      final w = (info['w'] as num?)?.toDouble();
      final h = (info['h'] as num?)?.toDouble();
      if (w != null && h != null && w > 0 && h > 0) {
        aspect = (w / h).clamp(0.55, 2.4);
      }
      if (info['duration'] is num) {
        duration = Duration(milliseconds: (info['duration'] as num).toInt());
      }
      if (info['thumbnail_url'] is String) {
        thumbMxc = info['thumbnail_url'] as String;
      }
    }
    final thumb = thumbMxc != null
        ? MatrixMedia.thumbnail(room.client, thumbMxc, width: 800, height: 800)
        : null;
    final source = MatrixMedia.download(room.client, MatrixMedia.mxcOf(event));

    void play() {
      if (source == null) return;
      Navigator.of(context).push(VideoPlayerScreen.route(
        url: source.url,
        headers: source.headers,
        title: event.senderFromMemoryOrFallback.calcDisplayname(),
      ));
    }

    return GestureDetector(
      onTap: widget.selectionMode ? widget.onTap : play,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: aspect,
              child: thumb == null
                  ? Container(color: Colors.black)
                  : Image.network(
                      thumb.url,
                      headers: thumb.headers,
                      fit: BoxFit.cover,
                      cacheWidth: 800,
                      errorBuilder: (_, __, ___) =>
                          Container(color: Colors.black),
                    ),
            ),
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 34),
            ),
            if (duration != null)
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    ChatTime.duration(duration),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fileLikeContent(BuildContext context,
      {required IconData icon, required String label}) {
    final c = context.allora;
    final fg = isMe ? c.onAccent : c.text;
    final body = stripReplyFallback(event.body);
    return InkWell(
      onTap: () {
        // Location: open the geo: URI in the device's map app.
        final geo = event.content['geo_uri'];
        if (geo is String && geo.isNotEmpty) {
          launchUrl(Uri.parse(geo), mode: LaunchMode.externalApplication);
          return;
        }
        // File: stream the authenticated download URL.
        final source =
            MatrixMedia.download(room.client, MatrixMedia.mxcOf(event));
        if (source == null) return;
        launchUrl(Uri.parse(source.url), mode: LaunchMode.externalApplication);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isMe ? c.onAccent.withValues(alpha: 0.22) : c.surfaceAlt,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: fg, size: 20),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  body.isEmpty ? label : body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14 * widget.fontScale,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
                Text(
                  'Tap to open',
                  style: TextStyle(
                      fontSize: 11.5, color: fg.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Footer: time + edited + status ────────────────────────────────────────

  Widget _footer(BuildContext context) {
    final c = context.allora;
    final color = _isImage
        ? (isMe ? c.onAccent : c.textSecondary)
        : isMe
            ? c.onAccent.withValues(alpha: 0.75)
            : c.textTertiary;
    final edited =
        event.hasAggregatedEvents(widget.timeline, RelationshipTypes.edit);

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (edited) ...[
          Text('edited',
              style: TextStyle(
                  fontSize: 10.5, fontStyle: FontStyle.italic, color: color)),
          const SizedBox(width: 4),
        ],
        Text(
          ChatTime.hourMinute(event.originServerTs),
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w500, color: color),
        ),
        if (isMe) ...[
          const SizedBox(width: 3),
          _StatusTicks(status: event.status, color: color, danger: c.danger),
        ],
      ],
    );
  }
}

/// sending → clock · sent → ✓ · synced (delivered & echoed) → ✓✓ ·
/// error → red alert. Animated between states.
class _StatusTicks extends StatelessWidget {
  final EventStatus status;
  final Color color;
  final Color danger;

  const _StatusTicks(
      {required this.status, required this.color, required this.danger});

  @override
  Widget build(BuildContext context) {
    Widget icon;
    if (status == EventStatus.error) {
      icon = Icon(Icons.error_rounded, size: 13, color: danger,
          key: const ValueKey('err'));
    } else if (status == EventStatus.sending) {
      icon = Icon(Icons.schedule_rounded, size: 12, color: color,
          key: const ValueKey('sending'));
    } else if (status == EventStatus.sent) {
      icon = Icon(Icons.check_rounded, size: 13, color: color,
          key: const ValueKey('sent'));
    } else {
      icon = Icon(Icons.done_all_rounded, size: 13, color: color,
          key: const ValueKey('synced'));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, anim) =>
          ScaleTransition(scale: anim, child: child),
      child: icon,
    );
  }
}

/// Quoted-message block shown inside a reply bubble.
class _ReplyPreview extends StatelessWidget {
  final String replyId;
  final Event? Function(String) resolveEvent;
  final bool isMine;
  final bool inMediaBubble;
  final void Function(String eventId) onJumpTo;

  const _ReplyPreview({
    required this.replyId,
    required this.resolveEvent,
    required this.isMine,
    required this.onJumpTo,
    required this.inMediaBubble,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.allora;

    return GestureDetector(
      onTap: () => onJumpTo(replyId),
      child: Container(
        margin: EdgeInsets.only(
            bottom: 6, top: inMediaBubble ? 2 : 0,
            left: inMediaBubble ? 2 : 0, right: inMediaBubble ? 2 : 0),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: (isMine ? Colors.white : c.accent).withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: isMine ? c.onAccent : c.accent),
            const SizedBox(width: 7),
            Flexible(child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 6, 10, 6),
              child: _replyBody(context),
            )),
          ],
        ),
      ),
    );
  }

  Widget _replyBody(BuildContext context) {
    final c = context.allora;
    final original = resolveEvent(replyId);
    final fg = isMine ? c.onAccent : c.text;
    final name = original == null
        ? 'Original message'
        : original.senderFromMemoryOrFallback.calcDisplayname();
    final body = original == null
        ? 'Tap to view'
        : original.redacted
            ? 'Message deleted'
            : stripReplyFallback(original.body);
    return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isMine ? c.onAccent : c.accent,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              body.replaceAll('\n', ' '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5, color: fg.withValues(alpha: 0.85)),
            ),
          ],
        );
  }
}

/// Aggregated reaction chips under a bubble; tap toggles your reaction.
class _ReactionsRow extends StatelessWidget {
  final Event event;
  final Timeline timeline;
  final bool isMe;
  final void Function(String key) onToggle;

  const _ReactionsRow({
    required this.event,
    required this.timeline,
    required this.isMe,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    final reactions =
        event.aggregatedEvents(timeline, RelationshipTypes.reaction);
    if (reactions.isEmpty) return const SizedBox.shrink();

    final myId = event.room.client.userID;
    final counts = <String, int>{};
    final mine = <String>{};
    for (final r in reactions) {
      if (r.redacted) continue;
      final relates = r.content['m.relates_to'];
      if (relates is! Map) continue;
      final key = relates['key']?.toString();
      if (key == null || key.isEmpty) continue;
      counts[key] = (counts[key] ?? 0) + 1;
      if (r.senderId == myId) mine.add(key);
    }
    if (counts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final entry in counts.entries)
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onToggle(entry.key);
              },
              child: TweenAnimationBuilder<double>(
                key: ValueKey('${entry.key}_${entry.value}'),
                tween: Tween(begin: 0.7, end: 1),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                builder: (context, t, child) =>
                    Transform.scale(scale: t, child: child),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: mine.contains(entry.key)
                        ? c.accent.withValues(alpha: 0.16)
                        : c.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: mine.contains(entry.key)
                          ? c.accent
                          : c.outline,
                      width: mine.contains(entry.key) ? 1.2 : 0.8,
                    ),
                  ),
                  child: Text(
                    entry.value > 1
                        ? '${entry.key} ${entry.value}'
                        : entry.key,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: c.text),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<int> waveform;
  final Color color;

  _WaveformPainter({required this.waveform, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;

    const bars = 28;
    final step = size.width / bars;
    final maxVal =
        waveform.reduce((a, b) => a > b ? a : b).toDouble().clamp(1.0, 1024.0);

    for (var i = 0; i < bars; i++) {
      final sample = waveform[(i * waveform.length ~/ bars)
          .clamp(0, waveform.length - 1)];
      final h = ((sample / maxVal) * size.height * 0.9)
          .clamp(3.0, size.height);
      final x = i * step + step / 2;
      canvas.drawLine(
        Offset(x, size.height / 2 - h / 2),
        Offset(x, size.height / 2 + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.color != color || old.waveform != waveform;
}

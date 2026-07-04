// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/chat_time.dart';
import '../../../data/services/ai_service.dart';
import '../../../data/services/scheduled_message_service.dart';
import '../../../data/settings/app_settings.dart';
import '../../ai/ai_assistant_sheet.dart';
import 'emoji_picker_sheet.dart';
import 'message_bubble.dart' show stripReplyFallback;

/// The message composer: expanding text field, emoji picker, attachment
/// sheet (gallery/camera), Allora AI assist, animated send button with
/// long-press scheduling, and reply/edit banners.
class ChatInputBar extends ConsumerStatefulWidget {
  final Room room;
  final Event? replyTo;
  final Event? editing;
  final VoidCallback onCancelReply;
  final VoidCallback onCancelEdit;
  final Future<void> Function(String text) onSend;
  final List<AiMessage> Function() aiContextBuilder;

  const ChatInputBar({
    super.key,
    required this.room,
    required this.replyTo,
    required this.editing,
    required this.onCancelReply,
    required this.onCancelEdit,
    required this.onSend,
    required this.aiContextBuilder,
  });

  @override
  ConsumerState<ChatInputBar> createState() => ChatInputBarState();
}

class ChatInputBarState extends ConsumerState<ChatInputBar> {
  final controller = TextEditingController();
  final _focus = FocusNode();
  final _picker = ImagePicker();
  Timer? _typingStop;
  bool _typingSent = false;
  bool _sending = false;

  bool get _hasText => controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editing != null && oldWidget.editing != widget.editing) {
      controller.text = stripReplyFallback(widget.editing!.body);
      controller.selection =
          TextSelection.collapsed(offset: controller.text.length);
      _focus.requestFocus();
    }
    if (widget.replyTo != null && oldWidget.replyTo != widget.replyTo) {
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _setTyping(false);
    _typingStop?.cancel();
    controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {}); // cheap: only this bar rebuilds
    if (_hasText) {
      _setTyping(true);
      _typingStop?.cancel();
      _typingStop = Timer(const Duration(seconds: 6), () => _setTyping(false));
    } else {
      _setTyping(false);
    }
  }

  void _setTyping(bool typing) {
    if (ref.read(settingsProvider).effectiveHideTyping) return;
    if (typing == _typingSent) return;
    _typingSent = typing;
    widget.room.setTyping(typing).catchError((_) {});
  }

  Future<void> _send() async {
    final text = controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    HapticFeedback.lightImpact();
    controller.clear();
    _setTyping(false);
    try {
      await widget.onSend(text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Scheduling ────────────────────────────────────────────────────────────

  Future<void> _scheduleSend() async {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.mediumImpact();

    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Schedule message',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
      helpText: 'Send at',
    );
    if (time == null || !mounted) return;

    final sendAt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (sendAt.isBefore(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That time is in the past.')));
      return;
    }

    await ScheduledMessageService.schedule(
      widget.room.client,
      roomId: widget.room.id,
      roomName: widget.room.displayname,
      body: text,
      sendAt: sendAt,
    );
    controller.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Scheduled for ${ChatTime.dayHeader(sendAt)} at ${ChatTime.hourMinute(sendAt)}')));
    }
  }

  // ── Attachments ───────────────────────────────────────────────────────────

  Future<void> _openAttachSheet() async {
    final c = context.allora;
    HapticFeedback.selectionClick();
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _attachOption(ctx, Icons.photo_library_rounded, 'Gallery',
                  c.accent, () => _pickAndSend(ImageSource.gallery)),
              _attachOption(ctx, Icons.photo_camera_rounded, 'Camera',
                  const Color(0xFF1FA45B), () => _pickAndSend(ImageSource.camera)),
              _attachOption(ctx, Icons.auto_awesome_rounded, 'Allora AI',
                  const Color(0xFF7C5CFC), _openAi),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachOption(BuildContext sheetContext, IconData icon, String label,
      Color color, VoidCallback onTap) {
    final c = context.allora;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.pop(sheetContext);
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSend(ImageSource source) async {
    XFile? file;
    try {
      file = await _picker.pickImage(
          source: source, imageQuality: 82, maxWidth: 2400);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(source == ImageSource.camera
                ? 'Camera unavailable.'
                : 'Could not open the gallery.')));
      }
      return;
    }
    if (file == null || !mounted) return;

    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final caption = await _confirmImage(bytes, file.name);
    if (caption == null || !mounted) return; // cancelled

    final messenger = ScaffoldMessenger.of(context);
    try {
      final matrixFile = MatrixImageFile(bytes: bytes, name: file.name);
      await widget.room.sendFileEvent(
        matrixFile,
        inReplyTo: widget.replyTo,
      );
      if (caption.trim().isNotEmpty) {
        await widget.room.sendTextEvent(caption.trim());
      }
      widget.onCancelReply();
    } catch (e) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Upload failed. Try again.')));
    }
  }

  /// Preview dialog before sending; returns caption ('' for none) or null.
  Future<String?> _confirmImage(Uint8List bytes, String name) {
    final captionController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = ctx.allora;
        return Dialog(
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: captionController,
                        decoration:
                            const InputDecoration(hintText: 'Add a caption…'),
                        maxLines: 2,
                        minLines: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: c.accent),
                      onPressed: () =>
                          Navigator.pop(ctx, captionController.text),
                      icon: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── AI & emoji ────────────────────────────────────────────────────────────

  Future<void> _openAi() async {
    final settings = ref.read(settingsProvider);
    if (!settings.aiEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Allora AI is turned off in Settings → AI Assistant.')));
      return;
    }
    final result = await showAiAssistantSheet(
      context,
      draft: controller.text,
      contextBuilder: widget.aiContextBuilder,
      translateLanguage: settings.aiTranslateLanguage,
    );
    if (result != null && result.trim().isNotEmpty) {
      controller.text = result.trim();
      controller.selection =
          TextSelection.collapsed(offset: controller.text.length);
      _focus.requestFocus();
    }
  }

  Future<void> _openEmoji() async {
    final emoji = await showEmojiPicker(context);
    if (emoji == null) return;
    final sel = controller.selection;
    final text = controller.text;
    final insertAt = sel.isValid ? sel.start : text.length;
    controller.text = text.replaceRange(insertAt, sel.isValid ? sel.end : insertAt, emoji);
    controller.selection =
        TextSelection.collapsed(offset: insertAt + emoji.length);
    _focus.requestFocus();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    final banner = widget.editing != null
        ? _banner(
            icon: Icons.edit_rounded,
            title: 'Editing message',
            body: stripReplyFallback(widget.editing!.body),
            onCancel: () {
              controller.clear();
              widget.onCancelEdit();
            },
          )
        : widget.replyTo != null
            ? _banner(
                icon: Icons.reply_rounded,
                title:
                    'Replying to ${widget.replyTo!.senderFromMemoryOrFallback.calcDisplayname()}',
                body: stripReplyFallback(widget.replyTo!.body),
                onCancel: widget.onCancelReply,
              )
            : null;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.outline)),
      ),
      padding: EdgeInsets.only(
        left: 6,
        right: 8,
        top: 6,
        bottom: 6 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (banner != null) banner,
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Attach',
                onPressed: _openAttachSheet,
                icon: Icon(Icons.add_circle_outline_rounded,
                    color: c.textSecondary, size: 24),
              ),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 140),
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          keyboardType: TextInputType.multiline,
                          style: TextStyle(fontSize: 15.5, color: c.text),
                          decoration: const InputDecoration(
                            hintText: 'Message',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.fromLTRB(16, 10, 4, 10),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Emoji',
                        onPressed: _openEmoji,
                        icon: Icon(Icons.emoji_emotions_outlined,
                            color: c.textTertiary, size: 22),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _hasText
                  ? GestureDetector(
                      onLongPress: _scheduleSend,
                      child: AnimatedScale(
                        scale: 1,
                        duration: const Duration(milliseconds: 150),
                        child: IconButton.filled(
                          tooltip: 'Send (hold to schedule)',
                          style: IconButton.styleFrom(
                            backgroundColor: c.accent,
                            minimumSize: const Size(44, 44),
                          ),
                          onPressed: _sending ? null : _send,
                          icon: const Icon(Icons.arrow_upward_rounded,
                              color: Colors.white, size: 22),
                        ),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Allora AI',
                      onPressed: _openAi,
                      icon: ShaderMask(
                        shaderCallback: (r) => LinearGradient(
                                colors: [c.accent, c.bubbleMineDeep])
                            .createShader(r),
                        child: const Icon(Icons.auto_awesome_rounded,
                            color: Colors.white, size: 24),
                      ),
                    ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _banner({
    required IconData icon,
    required String title,
    required String body,
    required VoidCallback onCancel,
  }) {
    final c = context.allora;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: c.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: c.accent)),
                Text(body.replaceAll('\n', ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 12.5, color: c.textSecondary)),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onCancel,
            icon: Icon(Icons.close_rounded, size: 18, color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

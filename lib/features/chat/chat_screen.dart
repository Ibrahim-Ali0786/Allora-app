// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/chat_time.dart';
import '../../core/widgets/allora_avatar.dart';
import '../../data/services/ai_service.dart';
import '../../data/settings/app_settings.dart';
import '../../screens/bridge/bridge_room_classifier.dart';
import '../../screens/networks/network_meta.dart';
import '../ai/ai_assistant_sheet.dart';
import '../chat_list/chat_list_providers.dart';
import 'chat_details_screen.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/disappearing_sheet.dart';
import 'widgets/emoji_picker_sheet.dart';
import 'widgets/forward_sheet.dart';
import 'widgets/message_bubble.dart';
import 'widgets/message_context_menu.dart';
import 'widgets/message_info_sheet.dart';
import 'widgets/typing_indicator_row.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final Room room;
  const ChatScreen({super.key, required this.room});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  Timeline? _timeline;
  bool _loadFailed = false;
  final _scroll = ScrollController();
  final _inputKey = GlobalKey<ChatInputBarState>();

  Event? _replyTo;
  Event? _editing;
  final Set<String> _selected = {};
  String? _highlightedId;
  Timer? _highlightTimer;

  int _unreadAtOpen = 0;
  bool _requestingHistory = false;
  bool _showJumpButton = false;

  // In-chat search
  bool _searchOpen = false;
  final _searchController = TextEditingController();
  List<Event> _matches = const [];
  int _matchIndex = 0;

  // Smart replies
  List<String> _smartReplies = const [];
  String? _smartRepliesForEvent;
  Timer? _smartReplyDebounce;
  static final Map<String, List<String>> _smartReplyCache = {};

  Room get room => widget.room;
  bool get _selectionMode => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _unreadAtOpen = room.notificationCount;
    _scroll.addListener(_onScroll);
    _initTimeline();
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _smartReplyDebounce?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchController.dispose();
    _timeline?.cancelSubscriptions();
    super.dispose();
  }

  Future<void> _initTimeline() async {
    try {
      final timeline = await room.getTimeline(onUpdate: _onTimelineUpdate);
      if (!mounted) {
        timeline.cancelSubscriptions();
        return;
      }
      setState(() => _timeline = timeline);
      _markRead();
      _scheduleSmartReplies();
    } catch (e) {
      debugPrint('ChatScreen: timeline init failed: $e');
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  void _onTimelineUpdate() {
    if (!mounted) return;
    setState(() {});
    // At (or near) the bottom: keep the room read as new messages arrive.
    if (_scroll.hasClients && _scroll.offset < 80) {
      _markRead();
    }
    _scheduleSmartReplies();
  }

  void _onScroll() {
    final show = _scroll.hasClients && _scroll.offset > 600;
    if (show != _showJumpButton) setState(() => _showJumpButton = show);

    final timeline = _timeline;
    if (timeline == null || _requestingHistory) return;
    if (_scroll.hasClients &&
        _scroll.position.maxScrollExtent - _scroll.offset < 900 &&
        timeline.canRequestHistory) {
      _requestHistory(timeline);
    }
  }

  Future<void> _requestHistory(Timeline timeline) async {
    setState(() => _requestingHistory = true);
    try {
      await timeline.requestHistory(historyCount: 60);
    } catch (e) {
      debugPrint('ChatScreen: requestHistory failed: $e');
    } finally {
      if (mounted) setState(() => _requestingHistory = false);
    }
  }

  void _markRead() {
    if (ref.read(settingsProvider).effectiveHideReadReceipts) return;
    final last = room.lastEvent;
    if (last == null || room.notificationCount == 0) return;
    room.setReadMarker(last.eventId, mRead: last.eventId).catchError((e) {
      debugPrint('setReadMarker failed: $e');
    });
  }

  // ── Events shown in the list ─────────────────────────────────────────────

  bool _isVisible(Event e) {
    if (e.type == EventTypes.Message ||
        e.type == EventTypes.Encrypted ||
        e.type == EventTypes.Sticker) {
      // Edit events are folded into their target via getDisplayEvent.
      if (e.relationshipType == RelationshipTypes.edit) return false;
      return true;
    }
    return false;
  }

  List<Event> _visibleEvents() {
    final timeline = _timeline;
    if (timeline == null) return const [];
    return timeline.events.where(_isVisible).toList();
  }

  // ── Sending ───────────────────────────────────────────────────────────────

  Future<void> _send(String text) async {
    try {
      if (_editing != null) {
        await room.sendTextEvent(text, editEventId: _editing!.eventId);
        setState(() => _editing = null);
      } else {
        final reply = _replyTo;
        setState(() => _replyTo = null);
        await room.sendTextEvent(text, inReplyTo: reply);
      }
      if (_scroll.hasClients) {
        _scroll.animateTo(0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic);
      }
    } catch (e) {
      debugPrint('send failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Message not sent — check your connection.')));
      }
    }
  }

  Future<void> _toggleReaction(Event event, String key) async {
    final timeline = _timeline;
    if (timeline == null) return;
    try {
      final myId = room.client.userID;
      Event? mine;
      for (final r
          in event.aggregatedEvents(timeline, RelationshipTypes.reaction)) {
        if (r.redacted || r.senderId != myId) continue;
        final relates = r.content['m.relates_to'];
        if (relates is Map && relates['key'] == key) {
          mine = r;
          break;
        }
      }
      if (mine != null) {
        await room.redactEvent(mine.eventId);
      } else {
        await room.sendReaction(event.eventId, key);
      }
    } catch (e) {
      debugPrint('reaction failed: $e');
    }
  }

  // ── Navigation within the timeline ───────────────────────────────────────

  final Map<String, GlobalKey> _itemKeys = {};

  GlobalKey _keyFor(String eventId) =>
      _itemKeys.putIfAbsent(eventId, () => GlobalKey());

  Future<void> _jumpTo(String eventId) async {
    final key = _itemKeys[eventId];
    final ctx = key?.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: 0.4);
      _flash(eventId);
      return;
    }
    // Not built yet: walk towards it (bounded) while history loads.
    final events = _visibleEvents();
    final idx = events.indexWhere((e) => e.eventId == eventId);
    if (idx == -1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Message is further back in history.')));
      return;
    }
    _scroll.animateTo(
      (idx * 72.0).clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx2 = _itemKeys[eventId]?.currentContext;
      if (ctx2 != null) {
        Scrollable.ensureVisible(ctx2,
            duration: const Duration(milliseconds: 240), alignment: 0.4);
      }
      _flash(eventId);
    });
  }

  void _flash(String eventId) {
    _highlightTimer?.cancel();
    setState(() => _highlightedId = eventId);
    _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _highlightedId = null);
    });
  }

  // ── Smart replies ─────────────────────────────────────────────────────────

  void _scheduleSmartReplies() {
    final settings = ref.read(settingsProvider);
    if (!settings.aiEnabled || !settings.aiSmartReplies) return;
    _smartReplyDebounce?.cancel();
    _smartReplyDebounce =
        Timer(const Duration(milliseconds: 900), _loadSmartReplies);
  }

  Future<void> _loadSmartReplies() async {
    final events = _visibleEvents();
    if (events.isEmpty) return;
    final last = events.first;
    // Only suggest when the other side spoke last.
    if (last.senderId == room.client.userID || last.redacted) {
      if (_smartReplies.isNotEmpty && mounted) {
        setState(() => _smartReplies = const []);
      }
      return;
    }
    if (_smartRepliesForEvent == last.eventId) return;

    final cached = _smartReplyCache[last.eventId];
    if (cached != null) {
      setState(() {
        _smartReplies = cached;
        _smartRepliesForEvent = last.eventId;
      });
      return;
    }

    _smartRepliesForEvent = last.eventId;
    final context8 =
        AiService.contextFromTimeline(room, events.take(8).toList());
    final res = await AiService.smartReplies(context8);
    if (!mounted || _smartRepliesForEvent != last.eventId) return;
    if (res.ok && res.suggestions.isNotEmpty) {
      _smartReplyCache[last.eventId] = res.suggestions.take(3).toList();
      if (_smartReplyCache.length > 30) {
        _smartReplyCache.remove(_smartReplyCache.keys.first);
      }
      setState(() => _smartReplies = _smartReplyCache[last.eventId]!);
    } else {
      setState(() => _smartReplies = const []);
    }
  }

  // ── Context menu ─────────────────────────────────────────────────────────

  void _openContextMenu(Event displayEvent, Rect rect) {
    final isMe = displayEvent.senderId == room.client.userID;
    final isText = !displayEvent.redacted &&
        (displayEvent.content['msgtype'] == 'm.text' ||
            displayEvent.content['msgtype'] == null ||
            displayEvent.content['msgtype'] == 'm.notice' ||
            displayEvent.content['msgtype'] == 'm.emote');
    final settings = ref.read(settingsProvider);
    final starred =
        ref.read(settingsProvider.notifier).isStarred(displayEvent.eventId);
    final pinnedIds = _safePinnedIds();
    final isPinned = pinnedIds.contains(displayEvent.eventId);
    final body = stripReplyFallback(displayEvent.body);

    showMessageContextMenu(
      context: context,
      event: displayEvent,
      bubbleRect: rect,
      isMe: isMe,
      onReact: (emoji) => _toggleReaction(displayEvent, emoji),
      onMoreReactions: () async {
        final emoji = await showEmojiPicker(context);
        if (emoji != null) await _toggleReaction(displayEvent, emoji);
      },
      actions: [
        MessageMenuAction(
          icon: Icons.reply_rounded,
          label: 'Reply',
          onTap: () => setState(() {
            _editing = null;
            _replyTo = displayEvent;
          }),
        ),
        if (isText)
          MessageMenuAction(
            icon: Icons.copy_rounded,
            label: 'Copy',
            onTap: () {
              Clipboard.setData(ClipboardData(text: body));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied')));
            },
          ),
        MessageMenuAction(
          icon: Icons.forward_rounded,
          label: 'Forward',
          onTap: () => showForwardSheet(context, ref, event: displayEvent),
        ),
        MessageMenuAction(
          icon: starred ? Icons.star_rounded : Icons.star_outline_rounded,
          label: starred ? 'Unstar' : 'Star',
          onTap: () => ref.read(settingsProvider.notifier).toggleStarred(
                StarredMessage(
                  roomId: room.id,
                  eventId: displayEvent.eventId,
                  roomName: cleanRoomTitle(room.displayname),
                  senderName: displayEvent.senderFromMemoryOrFallback
                      .calcDisplayname(),
                  preview: body.isEmpty
                      ? (displayEvent.content['msgtype']?.toString() ??
                          'Message')
                      : body,
                  tsMs: displayEvent.originServerTs.millisecondsSinceEpoch,
                ),
              ),
        ),
        MessageMenuAction(
          icon: isPinned
              ? Icons.push_pin_outlined
              : Icons.push_pin_rounded,
          label: isPinned ? 'Unpin' : 'Pin',
          onTap: () => _togglePin(displayEvent, pinnedIds),
        ),
        if (isText && settings.aiEnabled) ...[
          MessageMenuAction(
            icon: Icons.translate_rounded,
            label: 'Translate',
            onTap: () => showAiResultSheet(
              context,
              title: 'Translation',
              icon: Icons.translate_rounded,
              future:
                  AiService.translate(body, settings.aiTranslateLanguage),
            ),
          ),
          MessageMenuAction(
            icon: Icons.psychology_alt_rounded,
            label: 'Explain',
            onTap: () => showAiResultSheet(
              context,
              title: 'Explanation',
              icon: Icons.psychology_alt_rounded,
              future: AiService.explain(body),
            ),
          ),
        ],
        if (isMe && isText && !displayEvent.redacted)
          MessageMenuAction(
            icon: Icons.edit_rounded,
            label: 'Edit',
            onTap: () => setState(() {
              _replyTo = null;
              _editing = displayEvent;
            }),
          ),
        MessageMenuAction(
          icon: Icons.check_circle_outline_rounded,
          label: 'Select',
          onTap: () => setState(() => _selected.add(displayEvent.eventId)),
        ),
        MessageMenuAction(
          icon: Icons.info_outline_rounded,
          label: 'Message info',
          onTap: () => showMessageInfoSheet(context, displayEvent),
        ),
        if (isMe && !displayEvent.redacted)
          MessageMenuAction(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            destructive: true,
            onTap: () => _confirmRedact([displayEvent.eventId]),
          ),
      ],
    );
  }

  List<String> _safePinnedIds() {
    try {
      return room.pinnedEventIds;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _togglePin(Event event, List<String> current) async {
    try {
      final next = List<String>.from(current);
      next.contains(event.eventId)
          ? next.remove(event.eventId)
          : next.add(event.eventId);
      await room.setPinnedEvents(next);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Pinning isn\u2019t allowed in this chat.')));
      }
    }
  }

  void _confirmRedact(List<String> eventIds) {
    final c = context.allora;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            eventIds.length == 1 ? 'Delete message?' : 'Delete ${eventIds.length} messages?'),
        content: Text(
          'The message will be removed for everyone in this chat.',
          style: TextStyle(color: c.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              for (final id in eventIds) {
                try {
                  await room.redactEvent(id);
                } catch (e) {
                  debugPrint('redact failed: $e');
                }
              }
              setState(() => _selected.clear());
            },
            child: Text('Delete', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
  }

  // ── Search in chat ────────────────────────────────────────────────────────

  void _runSearch(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        _matches = const [];
        _matchIndex = 0;
      });
      return;
    }
    final matches = _visibleEvents()
        .where((e) => !e.redacted && e.body.toLowerCase().contains(q))
        .toList();
    setState(() {
      _matches = matches;
      _matchIndex = 0;
    });
    if (matches.isNotEmpty) _jumpTo(matches.first.eventId);
  }

  void _stepMatch(int delta) {
    if (_matches.isEmpty) return;
    setState(() =>
        _matchIndex = (_matchIndex + delta + _matches.length) % _matches.length);
    _jumpTo(_matches[_matchIndex].eventId);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    ref.watch(syncTickProvider); // typing users / presence refresh
    final events = _visibleEvents();
    final eventById = {for (final e in events) e.eventId: e};

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: _selectionMode
          ? _selectionAppBar(events)
          : _chatAppBar(),
      body: Column(
        children: [
          if (_searchOpen) _searchBar(),
          _pinnedBanner(eventById),
          Expanded(
            child: Stack(
              children: [
                _timeline == null
                    ? _loadFailed
                        ? _errorState()
                        : const Center(
                            child:
                                CircularProgressIndicator(strokeWidth: 2.5))
                    : events.isEmpty
                        ? _emptyChat()
                        : _messageList(events, eventById),
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: AnimatedScale(
                    scale: _showJumpButton ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    child: FloatingActionButton.small(
                      heroTag: 'jump_bottom',
                      backgroundColor: c.surface,
                      foregroundColor: c.accent,
                      elevation: 2,
                      onPressed: () {
                        _scroll.animateTo(0,
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic);
                        _markRead();
                      },
                      child: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ),
                ),
              ],
            ),
          ),
          TypingIndicatorRow(room: room),
          if (_smartReplies.isNotEmpty && !_selectionMode)
            _smartReplyChips(),
          if (!_selectionMode)
            ChatInputBar(
              key: _inputKey,
              room: room,
              replyTo: _replyTo,
              editing: _editing,
              onCancelReply: () => setState(() => _replyTo = null),
              onCancelEdit: () => setState(() => _editing = null),
              onSend: _send,
              aiContextBuilder: () => AiService.contextFromTimeline(
                  room, _visibleEvents().take(20).toList()),
            ),
        ],
      ),
    );
  }

  PreferredSizeWidget _chatAppBar() {
    final c = context.allora;
    final title = cleanRoomTitle(room.displayname);
    final networkId =
        BridgeRoomClassifier.getNetworkForRoom(room, client: room.client);
    final network = networkId != null ? metaFor(networkId) : null;
    final typing = room.typingUsers
        .where((u) => u.id != room.client.userID)
        .toList();
    final settings = ref.read(settingsProvider);
    final ttl = settings.disappearingSeconds[room.id] ?? 0;

    final String subtitle;
    if (typing.isNotEmpty) {
      subtitle = room.isDirectChat
          ? 'typing…'
          : '${typing.first.calcDisplayname().split(' ').first} is typing…';
    } else if (network != null) {
      subtitle = network.displayName;
    } else if (!room.isDirectChat) {
      final count = room.summary.mJoinedMemberCount ?? 0;
      subtitle = count > 0 ? '$count members' : 'Group';
    } else {
      subtitle = 'Direct message';
    }

    return AppBar(
      titleSpacing: 0,
      leadingWidth: 42,
      title: InkWell(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ChatDetailsScreen(room: room))),
        child: Row(
          children: [
            Hero(
              tag: 'avatar_${room.id}',
              child: AlloraAvatar(
                name: title,
                mxcUri: room.avatar,
                client: room.client,
                size: 38,
                network: network,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: c.text),
                        ),
                      ),
                      if (ttl > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 5),
                          child: Icon(Icons.timer_outlined,
                              size: 13, color: c.textSecondary),
                        ),
                    ],
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      subtitle,
                      key: ValueKey(subtitle),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: typing.isNotEmpty
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: typing.isNotEmpty ? c.accent : c.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Search in chat',
          onPressed: () => setState(() {
            _searchOpen = !_searchOpen;
            if (!_searchOpen) {
              _searchController.clear();
              _matches = const [];
            }
          }),
          icon: Icon(_searchOpen ? Icons.close_rounded : Icons.search_rounded),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: _onMenuAction,
          itemBuilder: (ctx) {
            final settings = ref.read(settingsProvider);
            final muted = room.pushRuleState == PushRuleState.dontNotify;
            return [
              const PopupMenuItem(
                  value: 'details', child: Text('Chat details')),
              if (settings.aiEnabled) ...[
                const PopupMenuItem(
                    value: 'summarize', child: Text('✨ Summarize chat')),
                const PopupMenuItem(
                    value: 'tasks', child: Text('✨ Extract tasks & dates')),
              ],
              PopupMenuItem(
                  value: 'mute', child: Text(muted ? 'Unmute' : 'Mute')),
              const PopupMenuItem(
                  value: 'disappearing',
                  child: Text('Disappearing messages')),
              const PopupMenuItem(
                  value: 'select', child: Text('Select messages')),
            ];
          },
        ),
      ],
    );
  }

  void _onMenuAction(String action) {
    switch (action) {
      case 'details':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => ChatDetailsScreen(room: room)));
        break;
      case 'summarize':
        showAiResultSheet(
          context,
          title: 'Chat summary',
          icon: Icons.summarize_rounded,
          future: AiService.summarize(AiService.contextFromTimeline(
              room, _visibleEvents().take(60).toList(), limit: 60)),
        );
        break;
      case 'tasks':
        showAiResultSheet(
          context,
          title: 'Tasks & dates',
          icon: Icons.checklist_rounded,
          future: AiService.extractActions(AiService.contextFromTimeline(
              room, _visibleEvents().take(60).toList(), limit: 60)),
        );
        break;
      case 'mute':
        final muted = room.pushRuleState == PushRuleState.dontNotify;
        room
            .setPushRuleState(
                muted ? PushRuleState.notify : PushRuleState.dontNotify)
            .then((_) {
          if (mounted) setState(() {});
        }).catchError((_) {});
        break;
      case 'disappearing':
        showDisappearingSheet(context, ref, room);
        break;
      case 'select':
        final events = _visibleEvents();
        if (events.isNotEmpty) {
          setState(() => _selected.add(events.first.eventId));
        }
        break;
    }
  }

  PreferredSizeWidget _selectionAppBar(List<Event> events) {
    final c = context.allora;
    final selectedEvents =
        events.where((e) => _selected.contains(e.eventId)).toList();
    final allMine = selectedEvents
        .every((e) => e.senderId == room.client.userID && !e.redacted);

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: () => setState(() => _selected.clear()),
      ),
      title: Text('${_selected.length} selected'),
      actions: [
        IconButton(
          tooltip: 'Copy',
          icon: const Icon(Icons.copy_rounded),
          onPressed: () {
            final text = selectedEvents.reversed
                .map((e) => stripReplyFallback(e.body))
                .where((t) => t.isNotEmpty)
                .join('\n');
            Clipboard.setData(ClipboardData(text: text));
            setState(() => _selected.clear());
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Copied')));
          },
        ),
        if (selectedEvents.length == 1)
          IconButton(
            tooltip: 'Forward',
            icon: const Icon(Icons.forward_rounded),
            onPressed: () {
              final e = selectedEvents.first;
              setState(() => _selected.clear());
              showForwardSheet(context, ref, event: e);
            },
          ),
        IconButton(
          tooltip: 'Star',
          icon: const Icon(Icons.star_outline_rounded),
          onPressed: () {
            final notifier = ref.read(settingsProvider.notifier);
            for (final e in selectedEvents) {
              if (!notifier.isStarred(e.eventId)) {
                notifier.toggleStarred(StarredMessage(
                  roomId: room.id,
                  eventId: e.eventId,
                  roomName: cleanRoomTitle(room.displayname),
                  senderName:
                      e.senderFromMemoryOrFallback.calcDisplayname(),
                  preview: stripReplyFallback(e.body),
                  tsMs: e.originServerTs.millisecondsSinceEpoch,
                ));
              }
            }
            setState(() => _selected.clear());
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Starred')));
          },
        ),
        if (allMine)
          IconButton(
            tooltip: 'Delete',
            icon: Icon(Icons.delete_outline_rounded, color: c.danger),
            onPressed: () => _confirmRedact(_selected.toList()),
          ),
      ],
    );
  }

  Widget _searchBar() {
    final c = context.allora;
    return Container(
      color: c.surface,
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              onSubmitted: _runSearch,
              onChanged: (v) {
                if (v.isEmpty) _runSearch('');
              },
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Search in chat…',
                prefixIcon: Icon(Icons.search_rounded, size: 20),
                isDense: true,
              ),
            ),
          ),
          if (_matches.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('${_matchIndex + 1}/${_matches.length}',
                  style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _stepMatch(1),
            icon: Icon(Icons.keyboard_arrow_up_rounded, color: c.textSecondary),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _stepMatch(-1),
            icon: Icon(Icons.keyboard_arrow_down_rounded,
                color: c.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _pinnedBanner(Map<String, Event> eventById) {
    final c = context.allora;
    final pinnedIds = _safePinnedIds();
    if (pinnedIds.isEmpty) return const SizedBox.shrink();
    final id = pinnedIds.last;
    final event = eventById[id];
    final preview = event == null
        ? 'Pinned message'
        : stripReplyFallback(event.getDisplayEvent(_timeline!).body)
            .replaceAll('\n', ' ');

    return Material(
      color: c.surface,
      child: InkWell(
        onTap: () => _jumpTo(id),
        onLongPress: event == null
            ? null
            : () => _togglePin(event, pinnedIds),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.outline)),
          ),
          child: Row(
            children: [
              Icon(Icons.push_pin_rounded, size: 15, color: c.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pinned message',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: c.accent)),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              if (pinnedIds.length > 1)
                Text('${pinnedIds.length}',
                    style: TextStyle(fontSize: 12, color: c.textTertiary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messageList(List<Event> events, Map<String, Event> eventById) {
    final settings = ref.watch(settingsProvider);
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      itemCount: events.length + (_requestingHistory ? 1 : 0),
      cacheExtent: 900,
      itemBuilder: (context, i) {
        if (i >= events.length) {
          return const Padding(
            padding: EdgeInsets.all(14),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final event = events[i];
        final older = i + 1 < events.length ? events[i + 1] : null;
        final newer = i > 0 ? events[i - 1] : null;
        final displayEvent = event.getDisplayEvent(_timeline!);

        final children = <Widget>[];

        // Day separator (visually above this message).
        if (older == null ||
            !ChatTime.sameDay(
                older.originServerTs, event.originServerTs)) {
          children.add(_DayChip(date: event.originServerTs));
        }

        // Unread divider captured at open time.
        if (_unreadAtOpen > 0 &&
            i == _unreadAtOpen - 1 &&
            _unreadAtOpen <= events.length) {
          children.add(const _UnreadDivider());
        }

        children.add(RepaintBoundary(
          key: _keyFor(event.eventId),
          child: MessageBubble(
            event: displayEvent,
            timeline: _timeline!,
            older: older,
            newer: newer,
            selectionMode: _selectionMode,
            selected: _selected.contains(event.eventId),
            highlighted: _highlightedId == event.eventId,
            fontScale: settings.fontScale,
            resolveEvent: (id) => eventById[id],
            onLongPress: _openContextMenu,
            onSwipeReply: (e) => setState(() {
              _editing = null;
              _replyTo = e;
            }),
            onTap: () => setState(() {
              _selected.contains(event.eventId)
                  ? _selected.remove(event.eventId)
                  : _selected.add(event.eventId);
            }),
            onJumpTo: _jumpTo,
            onToggleReaction: _toggleReaction,
          ),
        ));

        return Column(children: children);
      },
    );
  }

  Widget _smartReplyChips() {
    final c = context.allora;
    return Container(
      height: 44,
      alignment: Alignment.centerLeft,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6, top: 8),
            child:
                Icon(Icons.auto_awesome_rounded, size: 15, color: c.accent),
          ),
          for (final reply in _smartReplies)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                backgroundColor: c.surface,
                side: BorderSide(color: c.outline),
                label: Text(reply,
                    style: TextStyle(fontSize: 13, color: c.text)),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() => _smartReplies = const []);
                  _send(reply);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyChat() {
    final c = context.allora;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.waving_hand_rounded, size: 44, color: c.accent),
          const SizedBox(height: 12),
          Text('Say hello',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: c.text)),
          const SizedBox(height: 4),
          Text('Messages you send appear here.',
              style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
        ],
      ),
    );
  }

  Widget _errorState() {
    final c = context.allora;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 44, color: c.textTertiary),
          const SizedBox(height: 12),
          Text('Couldn\u2019t load this chat',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: () {
              setState(() => _loadFailed = false);
              _initTimeline();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  final DateTime date;
  const _DayChip({required this.date});

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: c.surfaceAlt.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          ChatTime.dayHeader(date),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: c.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider();

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
      child: Row(
        children: [
          Expanded(child: Divider(color: c.accent.withValues(alpha: 0.4))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'UNREAD MESSAGES',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: c.accent,
              ),
            ),
          ),
          Expanded(child: Divider(color: c.accent.withValues(alpha: 0.4))),
        ],
      ),
    );
  }
}

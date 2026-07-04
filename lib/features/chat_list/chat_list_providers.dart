// ignore_for_file: deprecated_member_use
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/utils/throttle.dart';
import '../../data/services/hidden_rooms_store.dart';
import '../../data/services/room_wipe_service.dart';
import '../../data/settings/app_settings.dart';
import '../../data/settings/labels.dart';
import '../../providers/network_provider.dart';
import '../../screens/bridge/bridge_room_classifier.dart';
import '../../screens/networks/network_meta.dart';

/// Category filters shown as chips above the list.
enum ChatFilter { all, unread, people, groups }

extension ChatFilterLabel on ChatFilter {
  String get label {
    switch (this) {
      case ChatFilter.all:
        return 'All';
      case ChatFilter.unread:
        return 'Unread';
      case ChatFilter.people:
        return 'People';
      case ChatFilter.groups:
        return 'Groups';
    }
  }
}

final chatFilterProvider = StateProvider<ChatFilter>((_) => ChatFilter.all);
final networkFilterProvider = StateProvider<NetworkId?>((_) => null);
final chatSearchQueryProvider = StateProvider<String>((_) => '');

/// Coalesced sync ticks: instant first update, then at most ~3/sec no
/// matter how hard the bridges hammer /sync. Every chat-list rebuild hangs
/// off this single stream — no per-tile listeners, no polling.
final syncTickProvider = StreamProvider<int>((ref) {
  final client = ref.watch(matrixClientProvider);
  var tick = 0;
  return throttleLatest(client.onSync.stream, const Duration(milliseconds: 350))
      .map((_) => ++tick);
});

/// Everything a tile needs, computed once per sync tick instead of inside
/// every row's build.
class ChatEntry {
  final Room room;
  final NetworkMeta? network;
  final String title;
  final bool pinned;
  final bool muted;
  final bool typing;
  final int unreadCount;
  final bool markedUnread;
  final bool isGroup;
  final Event? lastEvent;
  final DateTime lastActivity;
  final List<Label> labels;

  const ChatEntry({
    required this.room,
    required this.network,
    required this.title,
    required this.pinned,
    required this.muted,
    required this.typing,
    required this.unreadCount,
    required this.markedUnread,
    required this.isGroup,
    required this.lastEvent,
    required this.lastActivity,
    this.labels = const [],
  });

  bool get isUnread => unreadCount > 0 || markedUnread;
}

class ChatListData {
  final List<ChatEntry> pinned;
  final List<ChatEntry> chats;
  final int archivedCount;
  final int totalUnread;

  const ChatListData({
    required this.pinned,
    required this.chats,
    required this.archivedCount,
    required this.totalUnread,
  });

  bool get isEmpty => pinned.isEmpty && chats.isEmpty;
}

final _bridgeTagPattern = RegExp(
    r'\s*\((?:WA|IG|FB|TG|X|Slack|Discord|Signal)\)\s*$',
    caseSensitive: false);

String cleanRoomTitle(String raw) {
  final cleaned = raw.replaceAll(_bridgeTagPattern, '').trim();
  return cleaned.isEmpty ? raw : cleaned;
}

/// The single source of truth for what the chat list shows.
///
/// Subtracts, in order: bridge management rooms, rooms of disconnected
/// networks, rooms queued for wipe (so a disconnect empties the UI in the
/// same frame), hidden chats, archived chats; then applies category/network
/// filters and the search query; finally sorts pinned-first by activity.
final chatListProvider = Provider<ChatListData>((ref) {
  ref.watch(syncTickProvider); // rebuild on (throttled) sync
  final client = ref.watch(matrixClientProvider);
  final networkState = ref.watch(networkHubProvider);
  final wiping = ref.watch(wipePendingProvider);
  final hidden = ref.watch(hiddenRoomsProvider);
  final settings = ref.watch(settingsProvider);
  final filter = ref.watch(chatFilterProvider);
  final networkFilter = ref.watch(networkFilterProvider);
  final labelFilter = ref.watch(labelFilterProvider);
  final labelsState = ref.watch(labelsProvider);
  final query = ref.watch(chatSearchQueryProvider).trim().toLowerCase();

  final connected = networkState.networks
      .where((n) => n.status == NetworkStatus.connected)
      .map((n) => n.meta.id)
      .toSet();

  final pinned = <ChatEntry>[];
  final chats = <ChatEntry>[];
  var archivedCount = 0;
  var totalUnread = 0;

  for (final room in client.rooms) {
    if (room.membership != Membership.join) continue;
    if (room.isSpace) continue;
    if (wiping.contains(room.id)) continue;
    if (hidden.contains(room.id)) continue; // hidden while network disconnected
    if (settings.hiddenChats.contains(room.id)) continue;
    if (BridgeRoomClassifier.isManagementRoom(room, client: client)) continue;

    final networkId = BridgeRoomClassifier.getNetworkForRoom(room, client: client);
    if (networkId != null && !connected.contains(networkId)) continue;

    final unread = room.notificationCount;
    if (unread > 0) totalUnread += unread;

    if (settings.archivedChats.contains(room.id)) {
      archivedCount++;
      continue;
    }
    if (networkFilter != null && networkId != networkFilter) continue;

    final roomLabels = labelsState.labelsFor(room.id);
    if (labelFilter != null &&
        !roomLabels.any((l) => l.id == labelFilter)) {
      continue;
    }

    final isGroup = !room.isDirectChat;
    final markedUnread = room.markedUnread;
    if (filter == ChatFilter.unread && unread == 0 && !markedUnread) continue;
    if (filter == ChatFilter.people && isGroup) continue;
    if (filter == ChatFilter.groups && !isGroup) continue;

    final title = cleanRoomTitle(room.displayname);
    if (query.isNotEmpty && !title.toLowerCase().contains(query)) continue;

    final lastEvent = room.lastEvent;
    final entry = ChatEntry(
      room: room,
      network: networkId != null ? metaFor(networkId) : null,
      title: title,
      pinned: settings.pinnedChats.contains(room.id),
      muted: room.pushRuleState == PushRuleState.dontNotify,
      typing: room.typingUsers
          .any((u) => u.id != client.userID && u.id.isNotEmpty),
      unreadCount: unread,
      markedUnread: markedUnread,
      isGroup: isGroup,
      lastEvent: lastEvent,
      lastActivity: lastEvent?.originServerTs ??
          DateTime.fromMillisecondsSinceEpoch(0),
      labels: roomLabels,
    );
    (entry.pinned ? pinned : chats).add(entry);
  }

  int byActivity(ChatEntry a, ChatEntry b) =>
      b.lastActivity.compareTo(a.lastActivity);
  pinned.sort(byActivity);
  chats.sort(byActivity);

  return ChatListData(
    pinned: pinned,
    chats: chats,
    archivedCount: archivedCount,
    totalUnread: totalUnread,
  );
});

/// Archived chats, for the dedicated screen.
final archivedChatsProvider = Provider<List<ChatEntry>>((ref) {
  ref.watch(syncTickProvider);
  final client = ref.watch(matrixClientProvider);
  final settings = ref.watch(settingsProvider);
  final wiping = ref.watch(wipePendingProvider);
  final hidden = ref.watch(hiddenRoomsProvider);

  final out = <ChatEntry>[];
  for (final id in settings.archivedChats) {
    final room = client.getRoomById(id);
    if (room == null || room.membership != Membership.join) continue;
    if (wiping.contains(room.id)) continue;
    if (hidden.contains(room.id)) continue;
    final networkId = BridgeRoomClassifier.getNetworkForRoom(room, client: client);
    final lastEvent = room.lastEvent;
    out.add(ChatEntry(
      room: room,
      network: networkId != null ? metaFor(networkId) : null,
      title: cleanRoomTitle(room.displayname),
      pinned: false,
      muted: room.pushRuleState == PushRuleState.dontNotify,
      typing: false,
      unreadCount: room.notificationCount,
      markedUnread: room.markedUnread,
      isGroup: !room.isDirectChat,
      lastEvent: lastEvent,
      lastActivity:
          lastEvent?.originServerTs ?? DateTime.fromMillisecondsSinceEpoch(0),
    ));
  }
  out.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
  return out;
});

/// Preview line + glyph for a room's latest event ("📷 Photo", "🎤 Voice
/// message", "You: on my way"...). Pure function → trivially testable.
class ChatPreview {
  final String text;
  final PreviewGlyph glyph;
  const ChatPreview(this.text, [this.glyph = PreviewGlyph.none]);
}

enum PreviewGlyph { none, photo, video, voice, file, location, sticker, deleted }

ChatPreview previewFor(Event? event, {required bool isGroup, String? myUserId}) {
  if (event == null) return const ChatPreview('No messages yet');
  if (event.redacted) {
    return const ChatPreview('Message deleted', PreviewGlyph.deleted);
  }

  final isMe = event.senderId == myUserId;
  String prefix = '';
  if (isMe) {
    prefix = 'You: ';
  } else if (isGroup) {
    final sender = event.senderFromMemoryOrFallback.calcDisplayname();
    final first = sender.split(' ').first;
    if (first.isNotEmpty) prefix = '$first: ';
  }

  final msgtype = event.content['msgtype'] as String? ?? '';
  final body = event.content['body']?.toString().trim() ?? '';

  switch (msgtype) {
    case 'm.image':
      return ChatPreview('${prefix}Photo', PreviewGlyph.photo);
    case 'm.video':
      return ChatPreview('${prefix}Video', PreviewGlyph.video);
    case 'm.audio':
      return ChatPreview('${prefix}Voice message', PreviewGlyph.voice);
    case 'm.file':
      return ChatPreview(
          '$prefix${body.isEmpty ? 'File' : body}', PreviewGlyph.file);
    case 'm.location':
      return ChatPreview('${prefix}Location', PreviewGlyph.location);
    case 'm.sticker':
      return ChatPreview('${prefix}Sticker', PreviewGlyph.sticker);
  }
  if (event.type == EventTypes.Encrypted) {
    return ChatPreview('${prefix}Encrypted message');
  }
  if (body.isEmpty) return ChatPreview('${prefix}Message');
  final flat = body.replaceAll(RegExp(r'\s+'), ' ');
  return ChatPreview('$prefix$flat');
}

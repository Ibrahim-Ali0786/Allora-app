// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/chat_time.dart';
import '../../core/utils/matrix_media.dart';
import '../../core/utils/throttle.dart';
import '../../core/widgets/allora_avatar.dart';
import '../../data/settings/app_settings.dart';
import '../../providers/network_provider.dart';
import '../../screens/bridge/bridge_room_classifier.dart';
import '../../screens/networks/network_meta.dart';
import '../chat/chat_screen.dart';
import '../chat/widgets/image_viewer.dart';
import '../chat_list/chat_list_providers.dart';

enum _SearchTab { chats, messages, media, links }

class _MessageHit {
  final Room room;
  final Event event;
  const _MessageHit(this.room, this.event);
}

/// Global search: chat names instantly; message text, shared media and
/// links via a bounded scan of the most recent conversations (newest 24
/// rooms × last ~100 events — cancellable, so typing stays fluid).
class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final _controller = TextEditingController();
  final _debouncer = Debouncer(const Duration(milliseconds: 350));
  _SearchTab _tab = _SearchTab.chats;
  String _query = '';
  bool _scanning = false;
  int _generation = 0;

  List<Room> _chatHits = const [];
  List<_MessageHit> _messageHits = const [];
  List<_MessageHit> _mediaHits = const [];
  List<_MessageHit> _linkHits = const [];

  static final _urlPattern =
      RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

  @override
  void dispose() {
    _generation++;
    _debouncer.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _query = value;
    _searchChats(); // instant
    _debouncer(() => _scanTimelines());
  }

  List<Room> _candidateRooms() {
    final client = ref.read(matrixClientProvider);
    final hidden = ref.read(settingsProvider).hiddenChats;
    final rooms = client.rooms
        .where((r) =>
            r.membership == Membership.join &&
            !r.isSpace &&
            !hidden.contains(r.id) &&
            !BridgeRoomClassifier.isManagementRoom(r, client: client))
        .toList()
      ..sort((a, b) {
        final at = a.lastEvent?.originServerTs ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.lastEvent?.originServerTs ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
    return rooms;
  }

  void _searchChats() {
    final q = _query.trim().toLowerCase();
    final rooms = _candidateRooms();
    setState(() {
      _chatHits = q.isEmpty
          ? rooms.take(12).toList()
          : rooms
              .where((r) =>
                  cleanRoomTitle(r.displayname).toLowerCase().contains(q))
              .take(30)
              .toList();
    });
  }

  Future<void> _scanTimelines() async {
    final gen = ++_generation;
    final q = _query.trim().toLowerCase();
    setState(() {
      _scanning = true;
      _messageHits = const [];
      _mediaHits = const [];
      _linkHits = const [];
    });

    final messages = <_MessageHit>[];
    final media = <_MessageHit>[];
    final links = <_MessageHit>[];

    for (final room in _candidateRooms().take(24)) {
      if (gen != _generation || !mounted) return;
      Timeline? timeline;
      try {
        timeline = await room.getTimeline();
        for (final event in timeline.events.take(120)) {
          if (event.type != EventTypes.Message || event.redacted) continue;
          final msgtype = event.content['msgtype'] as String? ?? 'm.text';
          final body = event.body;

          if (msgtype == 'm.image' && event.content['url'] is String) {
            media.add(_MessageHit(room, event));
          }
          final url = _urlPattern.firstMatch(body)?.group(0);
          if (url != null &&
              (q.isEmpty || url.toLowerCase().contains(q))) {
            links.add(_MessageHit(room, event));
          }
          if (q.isNotEmpty &&
              msgtype != 'm.image' &&
              body.toLowerCase().contains(q)) {
            messages.add(_MessageHit(room, event));
          }
        }
      } catch (_) {
        // Room without loadable timeline — skip.
      } finally {
        timeline?.cancelSubscriptions();
      }

      // Push partial results so the list fills in as the scan proceeds.
      if (gen == _generation && mounted) {
        setState(() {
          _messageHits = List.of(messages);
          _mediaHits = List.of(media);
          _linkHits = List.of(links);
        });
      }
    }

    if (gen == _generation && mounted) {
      setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextField(
            controller: _controller,
            autofocus: true,
            onChanged: _onQueryChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search everything…',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _controller.clear();
                        _onQueryChanged('');
                      },
                    )
                  : null,
              isDense: true,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                _tabChip(_SearchTab.chats, 'Chats', Icons.forum_rounded),
                _tabChip(
                    _SearchTab.messages, 'Messages', Icons.notes_rounded),
                _tabChip(_SearchTab.media, 'Media', Icons.photo_rounded),
                _tabChip(_SearchTab.links, 'Links', Icons.link_rounded),
              ],
            ),
          ),
          if (_scanning) LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: c.surfaceAlt,
          ),
          Expanded(child: _results()),
        ],
      ),
    );
  }

  Widget _tabChip(_SearchTab tab, String label, IconData icon) {
    final c = context.allora;
    final selected = _tab == tab;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          setState(() => _tab = tab);
          if (tab != _SearchTab.chats &&
              _messageHits.isEmpty &&
              _mediaHits.isEmpty &&
              _linkHits.isEmpty &&
              !_scanning) {
            _scanTimelines();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.accent : c.surfaceAlt,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 14, color: selected ? c.onAccent : c.textSecondary),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? c.onAccent : c.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _results() {
    final c = context.allora;
    switch (_tab) {
      case _SearchTab.chats:
        if (_chatHits.isEmpty) return _empty('No chats found');
        return ListView.builder(
          itemCount: _chatHits.length,
          itemBuilder: (context, i) {
            final room = _chatHits[i];
            final networkId = BridgeRoomClassifier.getNetworkForRoom(room,
                client: room.client);
            final title = cleanRoomTitle(room.displayname);
            return ListTile(
              leading: AlloraAvatar(
                name: title,
                mxcUri: room.avatar,
                client: room.client,
                size: 46,
                network: networkId != null ? metaFor(networkId) : null,
              ),
              title:
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                room.isDirectChat ? 'Direct message' : 'Group',
                style: TextStyle(fontSize: 12, color: c.textTertiary),
              ),
              onTap: () => _openRoom(room),
            );
          },
        );

      case _SearchTab.messages:
        if (_query.trim().isEmpty) {
          return _empty('Type to search message text');
        }
        if (_messageHits.isEmpty && !_scanning) {
          return _empty('No messages found in recent chats');
        }
        return ListView.builder(
          itemCount: _messageHits.length,
          itemBuilder: (context, i) => _messageTile(_messageHits[i]),
        );

      case _SearchTab.media:
        if (_mediaHits.isEmpty && !_scanning) {
          return _empty('No recent photos found');
        }
        return GridView.builder(
          padding: const EdgeInsets.all(10),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemCount: _mediaHits.length,
          itemBuilder: (context, i) {
            final hit = _mediaHits[i];
            final mxc = MatrixMedia.mxcOf(hit.event);
            final thumb = MatrixMedia.thumbnail(hit.room.client, mxc,
                width: 300, height: 300);
            final full = MatrixMedia.download(hit.room.client, mxc);
            if (thumb == null || full == null) return const SizedBox.shrink();
            return GestureDetector(
              onTap: () => Navigator.of(context).push(ImageViewerScreen.route(
                  url: full.url,
                  headers: full.headers,
                  heroTag: 'search_${hit.event.eventId}')),
              child: Hero(
                tag: 'search_${hit.event.eventId}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(thumb.url,
                      headers: thumb.headers,
                      fit: BoxFit.cover, cacheWidth: 300),
                ),
              ),
            );
          },
        );

      case _SearchTab.links:
        if (_linkHits.isEmpty && !_scanning) {
          return _empty('No links found in recent chats');
        }
        return ListView.builder(
          itemCount: _linkHits.length,
          itemBuilder: (context, i) => _messageTile(_linkHits[i], isLink: true),
        );
    }
  }

  Widget _messageTile(_MessageHit hit, {bool isLink = false}) {
    final c = context.allora;
    final title = cleanRoomTitle(hit.room.displayname);
    return ListTile(
      leading: AlloraAvatar(
        name: title,
        mxcUri: hit.room.avatar,
        client: hit.room.client,
        size: 44,
        showNetworkBadge: false,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          Text(ChatTime.listStamp(hit.event.originServerTs),
              style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
        ],
      ),
      subtitle: Text(
        hit.event.body.replaceAll('\n', ' '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: isLink ? c.accent : c.textSecondary,
        ),
      ),
      onTap: () => _openRoom(hit.room),
    );
  }

  Widget _empty(String message) {
    final c = context.allora;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: c.textTertiary),
        ),
      ),
    );
  }

  void _openRoom(Room room) {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => ChatScreen(room: room)));
  }
}

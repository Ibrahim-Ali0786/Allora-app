// ignore_for_file: depend_on_referenced_packages, unused_local_variable, deprecated_member_use
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';
import 'connect_networks_screen.dart';
import 'package:rxdart/rxdart.dart';
import './whatsapp/whatsapp_disconnect_service.dart';
import './networks/network_meta.dart';
import './networks/network_connection_cache.dart';
import './bridge/bridge_room_classifier.dart';

// ─── DESIGN TOKENS ────────────────────────────────────────────────────────────
class _C {
  static const Color bg = Color(0xFFF2F2F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFE5E5EA);
  static const Color label = Color(0xFF1C1C1E);
  static const Color labelSec = Color(0xFF6B6B6F);
  static const Color labelTer = Color(0xFFAEAEB2);
  static const Color accent = Color(0xFF007AFF);
  static const Color positive = Color(0xFF34C759);
  static const Color unreadBadge = Color(0xFF007AFF);
  static const Color drawerBg = Color(0xFF111214);
  static const Color drawerSel = Color(0xFF1E2027);
}

// ─── SCREEN ───────────────────────────────────────────────────────────────────

class ChatListScreen extends StatefulWidget {
  final Client client;
  const ChatListScreen({super.key, required this.client});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with SingleTickerProviderStateMixin {
  late Stream<void> _uiStream;
  late AnimationController _drawerCtrl;
  late Animation<double> _drawerAnim;
  bool _drawerOpen = false;
  NetworkId? _activeFilter;

  @override
  void initState() {
    super.initState();
    _uiStream = Rx.merge([
      widget.client.onSync.stream,
      widget.client.onRoomState.stream,
    ]);
    _drawerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 270),
    );
    _drawerAnim = CurvedAnimation(
      parent: _drawerCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    NetworkConnectionCache.notifier.addListener(_onCacheChange);

    // Resume any pending WhatsApp room cleanup from previous sessions
    _resumePendingCleanup();

    // Clear classifier cache on init to ensure fresh state
    BridgeRoomClassifier.clearCache();
  }

  Future<void> _resumePendingCleanup() async {
    try {
      await WhatsAppDisconnectService.resumePendingWipes(widget.client);
      if (mounted) {
        // Force rebuild after cleanup
        setState(() {
          BridgeRoomClassifier.clearCache();
        });
      }
    } catch (e) {
      debugPrint('Error resuming WhatsApp cleanup: $e');
    }
  }

  @override
  void dispose() {
    _drawerCtrl.dispose();
    NetworkConnectionCache.notifier.removeListener(_onCacheChange);
    super.dispose();
  }

  void _onCacheChange() {
    if (mounted) {
      // Clear classifier cache to force fresh identification of rooms
      // when network connection states change
      BridgeRoomClassifier.clearCache();
      setState(() {});
    }
  }

  void _openDrawer() {
    HapticFeedback.lightImpact();
    setState(() => _drawerOpen = true);
    _drawerCtrl.forward();
  }

  void _closeDrawer() {
    _drawerCtrl.reverse().then((_) {
      if (mounted) setState(() => _drawerOpen = false);
    });
  }

  void _selectFilter(NetworkId? id) {
    HapticFeedback.selectionClick();
    setState(() => _activeFilter = id);
    _closeDrawer();
  }

  // ── Room helpers ──────────────────────────────────────────────────────────

  static String _roomDisplayName(Room room) {
    String name = room.displayname;
    name = name
        .replaceAll(RegExp(r'\s*\(WA\)\s*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\(WhatsApp\)\s*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\(IG\)\s*$', caseSensitive: false), '')
        .trim();
    return name.isEmpty ? 'Unknown chat' : name;
  }

  static String _lastMsgPreview(Room room) {
    final evt = room.lastEvent;
    if (evt == null) return '';
    final mt = evt.content['msgtype'] as String?;
    if (mt == 'm.image') return '📷 Photo';
    if (mt == 'm.video') return '🎥 Video';
    if (mt == 'm.audio') return '🎵 Audio';
    if (mt == 'm.file') return '📎 File';
    return evt.body.trim();
  }

  List<Room> _visibleRooms(bool isWipePending) {
    return widget.client.rooms.where((room) {
      if (room.membership != Membership.join) return false;

      final name = room.displayname.toLowerCase().trim();
      final directId = (room.directChatMatrixID ?? '').toLowerCase();
      final roomId = room.id.toLowerCase();

      // ──────────────────────────────────────────────────────────────────────
      // STEP 1: Filter out management/bot rooms (these never show in inbox)
      // ──────────────────────────────────────────────────────────────────────
      if (BridgeRoomClassifier.isManagementRoom(room, client: widget.client)) {
        return false;
      }
      if (directId.contains('bot:allorachat.app')) return false;
      if (name.contains('status broadcast')) return false;

      // ──────────────────────────────────────────────────────────────────────
      // STEP 2: Classify the room to find which network it belongs to
      // ──────────────────────────────────────────────────────────────────────
      final netId = BridgeRoomClassifier.classify(room, client: widget.client);

      // ──────────────────────────────────────────────────────────────────────
      // STEP 3: For rooms we identified as belonging to a network, check if
      // that network is currently connected. If not, hide the room.
      // ──────────────────────────────────────────────────────────────────────
      if (netId != null) {
        final snap = NetworkConnectionCache.get(netId);

        // If network is marked as disconnected, hide all its rooms
        if (snap.hasData && !snap.connected) return false;
        if (snap.autoDetectSuppressed && !snap.connected) return false;

        // For WhatsApp specifically, also respect pending wipe flag
        if (netId == NetworkId.whatsapp && isWipePending) {
          return false;
        }
      }

      // ──────────────────────────────────────────────────────────────────────
      // STEP 4: Additional aggressive WhatsApp detection (fallback)
      // If the room looks like WhatsApp but didn't classify as such,
      // check if WhatsApp is disconnected and hide it anyway
      // ──────────────────────────────────────────────────────────────────────
      final looksLikeWhatsApp = name.contains('(wa)') ||
          name.contains('whatsapp') ||
          name.contains('wa ') ||
          roomId.contains('_whatsapp_') ||
          directId.contains('whatsapp');

      if (looksLikeWhatsApp || (netId == null && isWipePending)) {
        // Double-check: if WhatsApp service thinks this is a WhatsApp room
        // and WhatsApp is disconnected, hide it
        if (WhatsAppDisconnectService.isWhatsAppRoom(room,
            client: widget.client)) {
          final waSnap = NetworkConnectionCache.get(NetworkId.whatsapp);
          if (waSnap.hasData && !waSnap.connected) return false;
          if (isWipePending) return false;
        }
      }

      return true;
    }).toList()
      ..sort((a, b) {
        final at = a.lastEvent?.originServerTs ?? DateTime(0);
        final bt = b.lastEvent?.originServerTs ?? DateTime(0);
        return bt.compareTo(at);
      });
  }

  List<Room> _filteredRooms(List<Room> all) {
    if (_activeFilter == null) return all;
    return all
        .where((r) => BridgeRoomClassifier.classify(r) == _activeFilter)
        .toList();
  }

  int _unreadFor(NetworkId id, List<Room> all) => all
      .where((r) => BridgeRoomClassifier.classify(r) == id)
      .fold(0, (s, r) => s + r.notificationCount);

  int _totalUnread(List<Room> all) =>
      all.fold(0, (s, r) => s + r.notificationCount);

  List<NetworkMeta> _connectedNetworks() => kNetworks.where((n) {
        if (!n.available) return false;
        return NetworkConnectionCache.get(n.id).connected;
      }).toList();

  String _safeUtf8(String s) {
    try {
      return utf8.decode(utf8.encode(s), allowMalformed: false);
    } catch (_) {
      return String.fromCharCodes(
          s.codeUnits.where((c) => c >= 0x20 && c < 0x7F));
    }
  }

  static String _relTime(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: WhatsAppDisconnectService.isWipePendingNotifier,
      builder: (_, isWipePending, __) {
        return StreamBuilder<void>(
          stream: _uiStream,
          builder: (_, __) {
            final allRooms = _visibleRooms(isWipePending);
            final filtered = _filteredRooms(allRooms);
            final networks = _connectedNetworks();
            final activeMeta = _activeFilter == null
                ? null
                : kNetworks.where((n) => n.id == _activeFilter).firstOrNull;

            return Scaffold(
              backgroundColor: _C.bg,
              body: Stack(
                children: [
                  // ── MAIN PANEL ───────────────────────────────────────────
                  Column(
                    children: [
                      _AppBar(
                        title: activeMeta?.displayName ?? 'All Messages',
                        brandColor: activeMeta?.brandColor,
                        totalUnread: _totalUnread(allRooms),
                        onMenuTap: _openDrawer,
                        onConnectTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => ConnectNetworksScreen(
                                    client: widget.client))),
                      ),
                      Expanded(
                        child: filtered.isEmpty
                            ? _EmptyState(
                                networkId: _activeFilter,
                                onConnectTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => ConnectNetworksScreen(
                                            client: widget.client))),
                              )
                            : ListView.builder(
                                padding: EdgeInsets.zero,
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final room = filtered[i];
                                  final name =
                                      _safeUtf8(_roomDisplayName(room));
                                  final preview =
                                      _safeUtf8(_lastMsgPreview(room));
                                  final netId =
                                      BridgeRoomClassifier.classify(room);
                                  final netMeta = netId == null
                                      ? null
                                      : kNetworks
                                          .where((n) => n.id == netId)
                                          .firstOrNull;
                                  return _ChatTile(
                                    key: ValueKey(room.id),
                                    displayName: name,
                                    preview: preview,
                                    timestamp: room.lastEvent?.originServerTs,
                                    unread: room.notificationCount,
                                    networkMeta: netMeta,
                                    showNetworkBadge: _activeFilter == null,
                                    isLast: i == filtered.length - 1,
                                  );
                                },
                              ),
                      ),
                    ],
                  ),

                  // ── SCRIM ────────────────────────────────────────────────
                  if (_drawerOpen)
                    AnimatedBuilder(
                      animation: _drawerAnim,
                      builder: (_, __) => GestureDetector(
                        onTap: _closeDrawer,
                        child: Container(
                          color:
                              Colors.black.withOpacity(0.5 * _drawerAnim.value),
                        ),
                      ),
                    ),

                  // ── SLIDING DRAWER ───────────────────────────────────────
                  if (_drawerOpen)
                    AnimatedBuilder(
                      animation: _drawerAnim,
                      builder: (_, __) => Transform.translate(
                        offset: Offset(-260.0 * (1.0 - _drawerAnim.value), 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _Drawer(
                            networks: networks,
                            activeFilter: _activeFilter,
                            unreadFor: (id) => _unreadFor(id, allRooms),
                            totalUnread: _totalUnread(allRooms),
                            onSelect: _selectFilter,
                            onConnectTap: () {
                              _closeDrawer();
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => ConnectNetworksScreen(
                                          client: widget.client)));
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ─── APP BAR ─────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  final String title;
  final Color? brandColor;
  final int totalUnread;
  final VoidCallback onMenuTap;
  final VoidCallback onConnectTap;

  const _AppBar({
    required this.title,
    required this.totalUnread,
    required this.onMenuTap,
    required this.onConnectTap,
    this.brandColor,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      color: _C.surface,
      padding: EdgeInsets.only(top: top),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 56,
            child: Row(
              children: [
                // Hamburger with unread dot
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.menu_rounded,
                          color: _C.label, size: 24),
                      onPressed: onMenuTap,
                    ),
                    if (totalUnread > 0)
                      Positioned(
                        top: 10,
                        right: 8,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: _C.unreadBadge, shape: BoxShape.circle),
                        ),
                      ),
                  ],
                ),
                if (brandColor != null) ...[
                  Container(
                    width: 3,
                    height: 20,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                        color: brandColor,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _C.label,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_link_rounded,
                      color: _C.accent, size: 22),
                  tooltip: 'Connect network',
                  onPressed: onConnectTap,
                ),
              ],
            ),
          ),
          Container(height: 0.5, color: _C.divider),
        ],
      ),
    );
  }
}

// ─── DRAWER ───────────────────────────────────────────────────────────────────

class _Drawer extends StatelessWidget {
  final List<NetworkMeta> networks;
  final NetworkId? activeFilter;
  final int Function(NetworkId) unreadFor;
  final int totalUnread;
  final void Function(NetworkId?) onSelect;
  final VoidCallback onConnectTap;

  const _Drawer({
    required this.networks,
    required this.activeFilter,
    required this.unreadFor,
    required this.totalUnread,
    required this.onSelect,
    required this.onConnectTap,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      width: 260,
      height: double.infinity,
      color: _C.drawerBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: top + 20),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
            child: Text(
              'Allora',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white.withOpacity(0.95),
                letterSpacing: -0.6,
              ),
            ),
          ),
          _DrawerRow(
            icon: const Icon(Icons.all_inbox_rounded,
                color: Colors.white70, size: 17),
            label: 'All Messages',
            unread: totalUnread,
            selected: activeFilter == null,
            accentColor: _C.accent,
            onTap: () => onSelect(null),
          ),
          if (networks.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
              child: Text(
                'NETWORKS',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.9,
                  color: Colors.white.withOpacity(0.3),
                ),
              ),
            ),
            ...networks.map((net) => _DrawerRow(
                  icon: net.asset != null
                      ? Padding(
                          padding: const EdgeInsets.all(2),
                          child: Image.asset(net.asset!, width: 17, height: 17))
                      : Icon(net.icon, color: Colors.white70, size: 17),
                  label: net.displayName,
                  unread: unreadFor(net.id),
                  selected: activeFilter == net.id,
                  accentColor: net.brandColor,
                  onTap: () => onSelect(net.id),
                )),
          ],
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: _DrawerRow(
              icon: const Icon(Icons.add_link_rounded,
                  color: Colors.white38, size: 17),
              label: 'Connect network',
              unread: 0,
              selected: false,
              accentColor: _C.accent,
              onTap: onConnectTap,
            ),
          ),
          SizedBox(height: bottom + 8),
        ],
      ),
    );
  }
}

class _DrawerRow extends StatelessWidget {
  final Widget icon;
  final String label;
  final int unread;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  const _DrawerRow({
    required this.icon,
    required this.label,
    required this.unread,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1.5),
      child: Material(
        color: selected ? accentColor.withOpacity(0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          splashColor: accentColor.withOpacity(0.1),
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: selected
                        ? accentColor.withOpacity(0.25)
                        : Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(child: icon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected
                          ? Colors.white
                          : Colors.white.withOpacity(0.65),
                    ),
                  ),
                ),
                if (unread > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── CHAT TILE ────────────────────────────────────────────────────────────────

class _ChatTile extends StatelessWidget {
  final String displayName;
  final String preview;
  final DateTime? timestamp;
  final int unread;
  final NetworkMeta? networkMeta;
  final bool showNetworkBadge;
  final bool isLast;

  const _ChatTile({
    super.key,
    required this.displayName,
    required this.preview,
    required this.timestamp,
    required this.unread,
    required this.showNetworkBadge,
    required this.isLast,
    this.networkMeta,
  });

  static String _relTime(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}';
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = unread > 0;
    final initial = displayName.isNotEmpty
        ? displayName.characters.first.toUpperCase()
        : '?';
    final avatarClr = networkMeta?.brandColor ?? _C.accent;

    return Material(
      color: _C.surface,
      child: InkWell(
        onTap: () {},
        highlightColor: _C.bg,
        splashColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  // Avatar
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: avatarClr.withOpacity(0.13),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: avatarClr,
                            ),
                          ),
                        ),
                      ),
                      if (showNetworkBadge && networkMeta != null)
                        Positioned(
                          bottom: -1,
                          right: -1,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: networkMeta!.brandColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: _C.surface, width: 2),
                            ),
                            child: networkMeta!.asset != null
                                ? Padding(
                                    padding: const EdgeInsets.all(3.5),
                                    child: Image.asset(networkMeta!.asset!))
                                : Icon(networkMeta!.icon,
                                    color: Colors.white, size: 9),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 13),

                  // Text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Expanded(
                              child: Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: hasUnread
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: _C.label,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _relTime(timestamp),
                              style: TextStyle(
                                fontSize: 12,
                                color: hasUnread ? _C.accent : _C.labelTer,
                                fontWeight: hasUnread
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                preview.isEmpty ? 'No messages yet' : preview,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: hasUnread ? _C.labelSec : _C.labelTer,
                                  fontWeight: hasUnread
                                      ? FontWeight.w500
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (hasUnread) ...[
                              const SizedBox(width: 6),
                              Container(
                                constraints: const BoxConstraints(minWidth: 20),
                                height: 20,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 5),
                                decoration: BoxDecoration(
                                  color: _C.unreadBadge,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    unread > 99 ? '99+' : '$unread',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!isLast)
              Padding(
                padding: const EdgeInsets.only(left: 79),
                child: Container(height: 0.5, color: _C.divider),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── EMPTY STATE ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final NetworkId? networkId;
  final VoidCallback onConnectTap;

  const _EmptyState({this.networkId, required this.onConnectTap});

  @override
  Widget build(BuildContext context) {
    final meta = networkId == null
        ? null
        : kNetworks.where((n) => n.id == networkId).firstOrNull;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: (meta?.brandColor ?? _C.accent).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: meta?.asset != null
                    ? Padding(
                        padding: const EdgeInsets.all(18),
                        child: Image.asset(meta!.asset!))
                    : Icon(
                        meta?.icon ?? Icons.forum_rounded,
                        color: meta?.brandColor ?? _C.accent,
                        size: 34,
                      ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              meta != null
                  ? 'No ${meta.displayName} chats yet'
                  : 'Your inbox is empty',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _C.label,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              meta != null
                  ? 'Your ${meta.displayName} chats will appear here.'
                  : 'Connect a messaging network to get started.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14.5,
                color: _C.labelSec,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onConnectTap,
              icon: const Icon(Icons.add_link_rounded, size: 18),
              label: const Text('Connect a network'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

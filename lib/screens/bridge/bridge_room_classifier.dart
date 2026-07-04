// ignore_for_file: deprecated_member_use
import 'package:matrix/matrix.dart';
import '../networks/network_meta.dart';

class BridgeRoomClassifier {
  BridgeRoomClassifier._();

  /// Returns the NetworkId this room belongs to, or null if it's a native Matrix room.
  static NetworkId? getNetworkForRoom(Room room, {Client? client}) {
    for (final network in NetworkId.values) {
      if (isRoomForNetwork(room, network, client: client)) {
        return network;
      }
    }
    return null;
  }

  /// Per-room classification cache. A portal room's network never changes
  /// after creation, so once we know the answer for a room id we never need
  /// to recompute it — in particular we never need to re-walk
  /// `room.getParticipants()` for it again. This is what keeps the chat
  /// list responsive when dozens of portal rooms arrive in a burst right
  /// after connecting a network: without this, every single sync tick was
  /// re-running the most expensive check for every room, every time.
  static final Map<String, NetworkId?> _cache = {};

  /// Call this once a room is actually gone (left + forgotten) so the cache
  /// doesn't hold a stale entry for an id that no longer exists. Safe to
  /// skip — a few thousand stale entries cost only a tiny amount of memory
  /// — but tidy to call from the wipe service.
  static void forget(String roomId) => _cache.remove(roomId);

  static void clearCache() => _cache.clear();

  /// Force clear and rebuild cache for a specific network. Call this when
  /// a network connects or disconnects to ensure fresh classification.
  static void clearCacheForNetwork(NetworkId networkId) {
    _cache.removeWhere((_, classifiedId) => classifiedId == networkId);
  }

  /// Returns the [NetworkId] for a bridge portal room, or null if the room
  /// is not a bridge portal (or is a management room).
  ///
  /// Pass [client] when you have it — it lets this method recognise a
  /// network's bot management room by an *exact* match on the bot's own
  /// Matrix ID (e.g. "@whatsappbot:yourserver"), which is far more reliable
  /// than matching on display names. Display names can be empty, stale, or
  /// just not what you expect while profiles are still loading — and a
  /// false negative here (failing to recognise the management room) is what
  /// lets it accidentally get swept up as a "portal" by disconnect logic
  /// elsewhere. Without [client] this falls back to display-name
  /// heuristics only.
  static NetworkId? classify(Room room, {Client? client}) {
    if (room.membership != Membership.join) return null;

    // Only positive classifications are cached. A portal's network never
    // changes once known, so caching a match is safe — but caching a *null*
    // is not: early in sync a group portal's `m.bridge` state and puppet
    // members may not be loaded yet, so it looks native. If we cached that
    // null it would stay "native" forever (shown even after the network is
    // disconnected, never wiped). Re-evaluating nulls every call fixes that;
    // the checks are cheap and the result caches the moment it resolves.
    final cached = _cache[room.id];
    if (cached != null) return cached;

    final result = _classifyUncached(room, client: client);
    if (result != null) _cache[room.id] = result;
    return result;
  }

  static NetworkId? _classifyUncached(Room room, {Client? client}) {
    // ── 0. Canonical bridge state (most reliable, works for group portals) ──
    // mautrix/matrix bridges stamp every portal — direct chats AND groups —
    // with an `m.bridge` (and `uk.half-shot.bridge`) state event carrying
    // `protocol.id`. This never depends on room names, aliases, or which
    // members are currently loaded, which is exactly why WhatsApp *groups*
    // used to slip through and linger after a disconnect.
    final protocolNet = _networkFromBridgeState(room);
    if (protocolNet != null) return protocolNet;

    final name = room.displayname.toLowerCase().trim();
    final directId = (room.directChatMatrixID ?? '').toLowerCase();
    final roomId = room.id.toLowerCase();
    final canonicalAlias = (room.canonicalAlias).toLowerCase();
    final userDomain = client?.userID?.split(':').last.toLowerCase();

    for (final net in kNetworks) {
      if (!net.available) continue;
      final alias = net.botAlias; // e.g. "whatsapp"
      final nameTag = net.nameTag; // e.g. "wa"

      // ── Canonical management-room exclusion (most reliable) ─────────────
      if (userDomain != null && directId == net.botMxid(userDomain)) {
        continue;
      }

      // ── Fallback management-room exclusions (heuristic) ──────────────────
      if (name == alias) continue;
      if (name == '$alias bridge bot') continue;
      if (name == '${alias}bot') continue;

      // ── Portal signals ───────────────────────────────────────────────────
      // 1. Tag in name, e.g. "(WA)", "(ig)", "(discord)"
      if (name.contains('($nameTag)')) return net.id;

      // 2. Network-specific extra name signals, e.g. WhatsApp's
      //    "status broadcast" room.
      for (final signal in net.extraNameSignals) {
        if (name.contains(signal)) return net.id;
      }

      // 3. Room ID / canonical alias contains an alias fragment, e.g.
      //    "#whatsapp_<jid>:server" — mautrix commonly aliases portals.
      if (roomId.contains('_${alias}_')) return net.id;
      if (canonicalAlias.contains('${alias}_') ||
          canonicalAlias.contains('_$alias')) {
        return net.id;
      }

      // 4. Direct chat partner is the bridge bot / puppet
      if (directId.contains('${alias}bot')) return net.id;
      if (directId.contains('$alias-bot')) return net.id;
      if (directId.contains('${alias}_') || directId.contains(':$alias')) {
        return net.id;
      }
      if (directId.contains(alias) && directId.isNotEmpty) return net.id;

      // 5. Room display name starts with "<alias> bridge bot," (portal seed)
      if (name.startsWith('$alias bridge bot,')) return net.id;

      // 6. Participant MXID check — catches puppet-only group portals (the
      //    bridge bot itself is often NOT a member of group portals, only
      //    the puppets "@whatsapp_<number>:server" are). Cached, so this
      //    only ever runs once per room.
      if (_hasNetworkPuppet(room, alias)) return net.id;
    }

    return null; // Not a recognised bridge portal.
  }

  /// Reads the room's `m.bridge` / `uk.half-shot.bridge` state and maps the
  /// advertised protocol id to a network. Defensive: any absence or shape
  /// mismatch just yields null (we fall back to heuristics).
  static NetworkId? _networkFromBridgeState(Room room) {
    // Accessed via `dynamic` so this compiles regardless of the exact static
    // type of `room.states[...]` across SDK versions; wrapped in try/catch so
    // any shape surprise degrades to "unknown" (the puppet-mxid check below
    // still classifies the room correctly).
    try {
      for (final type in const ['m.bridge', 'uk.half-shot.bridge']) {
        final dynamic byStateKey = room.states[type];
        if (byStateKey == null) continue;
        final Iterable events =
            byStateKey is Map ? byStateKey.values : const [];
        for (final dynamic event in events) {
          final dynamic content = event.content;
          if (content is! Map) continue;
          for (final key in const ['protocol', 'network']) {
            final dynamic sub = content[key];
            if (sub is Map) {
              final id = sub['id']?.toString();
              if (id != null && id.isNotEmpty) {
                final net = networkForBridgeProtocol(id);
                if (net != null) return net;
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// True if any participant's MXID localpart identifies a bridge puppet or
  /// bot for [alias]: "@whatsappbot:…" or "@whatsapp_<id>:…".
  static bool _hasNetworkPuppet(Room room, String alias) {
    for (final m in room.getParticipants()) {
      final mxid = m.id.toLowerCase();
      final localpart =
          mxid.startsWith('@') ? mxid.substring(1).split(':').first : mxid;
      if (localpart == alias ||
          localpart.startsWith('${alias}bot') ||
          localpart.startsWith('$alias-') ||
          localpart.startsWith('${alias}_')) {
        return true;
      }
    }
    return false;
  }

  /// Returns true if this room is a bridge management room (the control room
  /// you use to run `!wa login`, `list-logins`, etc.), not a chat portal.
  static bool isManagementRoom(Room room, {Client? client}) {
    final userDomain = client?.userID?.split(':').last.toLowerCase();
    final directId = (room.directChatMatrixID ?? '').toLowerCase();
    final directLocalpart = directId.startsWith('@')
        ? directId.substring(1).split(':').first
        : directId;
    final name = room.displayname.toLowerCase().trim();

    for (final n in kNetworks) {
      // Exact bot mxid on our own server.
      if (userDomain != null && directId == n.botMxid(userDomain)) return true;
      // DM partner localpart is the bridge bot, e.g. "@whatsappbot:anything".
      // This is what hides the "WhatsApp login" bot chat from the inbox.
      if (directLocalpart == '${n.botAlias}bot' ||
          directLocalpart == '${n.botAlias}-bot') {
        return true;
      }
      // Name heuristics.
      if (name == n.botAlias ||
          name == '${n.botAlias} bridge bot' ||
          name == '${n.botAlias}bot' ||
          name == '${n.botAlias} bot') {
        return true;
      }
    }

    // Also: a strict 1:1 room whose only other member is a bridge bot, even
    // when directChatMatrixID isn't populated.
    if (client != null) {
      final others = room
          .getParticipants()
          .where((m) => m.id != client.userID)
          .toList();
      if (others.length == 1) {
        final lp = others.first.id.startsWith('@')
            ? others.first.id.substring(1).split(':').first.toLowerCase()
            : others.first.id.toLowerCase();
        for (final n in kNetworks) {
          if (lp == '${n.botAlias}bot' || lp == '${n.botAlias}-bot') {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Convenience: returns true if the room belongs to [networkId].
  static bool isRoomForNetwork(Room room, NetworkId networkId,
          {Client? client}) =>
      classify(room, client: client) == networkId;

  /// Returns all rooms belonging to [networkId] from [rooms].
  static List<Room> roomsForNetwork(List<Room> rooms, NetworkId networkId,
          {Client? client}) =>
      rooms
          .where((r) => isRoomForNetwork(r, networkId, client: client))
          .toList();

  /// Discovers the *real* bridge-bot MXID for [networkId] by reading the
  /// `bridgebot` field of any of that network's portal `m.bridge` state
  /// events. This is far more reliable than guessing "@whatsappbot:server":
  /// it's whatever the bridge actually runs as. Returns null if no portal
  /// advertises one (falls back to the guessed mxid at the call site).
  static String? findBridgeBotMxid(Client client, NetworkId networkId) {
    try {
      for (final room in client.rooms) {
        if (room.membership != Membership.join) continue;
        for (final type in const ['m.bridge', 'uk.half-shot.bridge']) {
          final dynamic byStateKey = room.states[type];
          if (byStateKey == null) continue;
          final Iterable events =
              byStateKey is Map ? byStateKey.values : const [];
          for (final dynamic event in events) {
            final dynamic content = event.content;
            if (content is! Map) continue;
            final dynamic protocol = content['protocol'];
            if (protocol is! Map) continue;
            final id = protocol['id']?.toString();
            if (id == null || networkForBridgeProtocol(id) != networkId) {
              continue;
            }
            final bot = content['bridgebot']?.toString();
            if (bot != null && bot.startsWith('@')) return bot;
          }
        }
      }
    } catch (_) {}
    return null;
  }
}

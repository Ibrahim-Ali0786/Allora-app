// ignore_for_file: deprecated_member_use
import 'package:matrix/matrix.dart';
import '../networks/network_meta.dart';

class BridgeRoomClassifier {
  BridgeRoomClassifier._();

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

    if (_cache.containsKey(room.id)) return _cache[room.id];

    final result = _classifyUncached(room, client: client);
    _cache[room.id] = result;
    return result;
  }

  static NetworkId? _classifyUncached(Room room, {Client? client}) {
    final name = room.displayname.toLowerCase().trim();
    final directId = (room.directChatMatrixID ?? '').toLowerCase();
    final roomId = room.id.toLowerCase();
    final userDomain = client?.userID?.split(':').last.toLowerCase();

    for (final net in kNetworks) {
      if (!net.available) continue;
      final alias = net.botAlias; // e.g. "whatsapp"
      final nameTag = net.nameTag; // e.g. "wa"

      // ── Canonical management-room exclusion (most reliable) ─────────────
      // If we know the bot's exact mxid, an exact match on the DM partner
      // wins over every other signal below: this room IS the bot's 1:1
      // control room, never a chat portal, full stop — regardless of what
      // its display name happens to be.
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

      // 3. Room ID contains alias fragment, e.g. "!xxx_whatsapp_yyy:server"
      if (roomId.contains('_${alias}_')) return net.id;

      // 4. Direct chat partner is the bridge bot
      if (directId.contains('${alias}bot')) return net.id;
      if (directId.contains('$alias-bot')) return net.id;
      if (directId.contains(alias) && directId.isNotEmpty) return net.id;

      // 5. Room display name starts with "<alias> bridge bot," (portal seed)
      if (name.startsWith('$alias bridge bot,')) return net.id;

      // 6. Participant MXID check — most reliable but also most expensive.
      //    Only run this if none of the cheaper checks fired, and because
      //    the result is cached, this only ever runs once per room, ever.
      for (final m in room.getParticipants()) {
        final mxid = m.id.toLowerCase();
        if (mxid.contains('${alias}bot') || mxid.contains('$alias-bot')) {
          return net.id;
        }
      }
    }

    return null; // Not a recognised bridge portal.
  }

  /// Returns true if this room is a bridge management room (the control room
  /// you use to run `!wa login`, `list-logins`, etc.), not a chat portal.
  static bool isManagementRoom(Room room, {Client? client}) {
    final userDomain = client?.userID?.split(':').last.toLowerCase();
    final directId = (room.directChatMatrixID ?? '').toLowerCase();
    final name = room.displayname.toLowerCase().trim();

    for (final n in kNetworks) {
      if (userDomain != null && directId == n.botMxid(userDomain)) {
        return true;
      }
      if (name == n.botAlias ||
          name == '${n.botAlias} bridge bot' ||
          name == '${n.botAlias}bot') {
        return true;
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
}

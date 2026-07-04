// ignore_for_file: deprecated_member_use
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../screens/bridge/bridge_room_classifier.dart';
import '../../screens/networks/network_connection_cache.dart';
import '../../screens/networks/network_meta.dart';
import 'connection_manager.dart';
import 'hidden_rooms_store.dart';
import 'room_wipe_service.dart';

/// Result of a network disconnect, so the UI can tell the user the truth
/// about what actually happened on the remote side.
class DisconnectResult {
  /// True when the bridge bot was reachable and a logout command was sent —
  /// i.e. the remote session was asked to terminate.
  final bool remoteLogoutSent;

  /// Number of portal rooms scheduled for immediate removal.
  final int roomsWiped;

  const DisconnectResult({
    required this.remoteLogoutSent,
    required this.roomsWiped,
  });

  /// Honest user-facing summary for the "logout impossible" case required
  /// by the product spec.
  String get userMessage => remoteLogoutSent
      ? 'Your account was signed out and removed from Allora.'
      : 'Your Allora connection has been removed. You may still be logged '
          'into the official application.';
}

/// One place that knows how to *fully* take an account out of Allora:
///
///   1. sticky-mark the network disconnected (survives restarts, can't be
///      flipped back by a lagging probe),
///   2. tell the bridge bot to revoke the remote session (`logout`),
///   3. instantly wipe every portal room (chats, groups, channels, avatars,
///      unread counts — they all live on those rooms),
///   4. clear the classifier cache and per-chat preferences,
///   5. refresh the connection manager so every status pill updates live.
///
/// Used by every network's disconnect sheet — WhatsApp is no longer a
/// special case.
class AccountLifecycleService {
  AccountLifecycleService._();

  /// Called by the per-network account sheets.
  static Future<DisconnectResult> disconnectNetwork(
    Client client,
    NetworkId networkId, {
    void Function(Iterable<String> roomIds)? onRoomsForgotten,
  }) async {
    final meta = metaFor(networkId);

    // 1. Sticky disconnect first — even if everything below fails, the app
    //    never shows a ghost "Connected" state again.
    await NetworkConnectionCache.markDisconnected(networkId);
    ConnectionManager.instance?.noteDisconnected(networkId);

    // 2. Ask the bridge to revoke the remote session. This is what actually
    //    unlinks the device on WhatsApp/etc. — without it the account keeps
    //    showing as a linked device in the official app.
    final botRoom = findManagementRoom(client, networkId);
    var remoteLogoutSent = false;
    if (botRoom != null) {
      try {
        // mautrix accepts a bare `logout` in the management DM. Newer
        // (bridgev2) builds also accept `logout all`; we send the plain
        // form first, then a best-effort `logout all` a beat later so a
        // multi-login setup is fully cleared. Failures are non-fatal.
        await botRoom.sendTextEvent('logout');
        remoteLogoutSent = true;
        await Future.delayed(const Duration(seconds: 2));
        try {
          await botRoom.sendTextEvent('logout all');
        } catch (_) {}
        // Give the bridge a moment to process the unlink before we start
        // leaving portals; some bridges cancel the logout if the portal
        // membership churns mid-command.
        await Future.delayed(const Duration(milliseconds: 1500));
      } catch (e) {
        debugPrint('AccountLifecycle: logout command failed for '
            '${meta.displayName}: $e — continuing with local cleanup.');
      }
    }

    // 3. Robustly collect every portal room for this network. Cheap checks
    //    (m.bridge state, name tags, room id) run first; for anything still
    //    unclassified we load its members and retry, because mautrix *group*
    //    portals are often only identifiable by their puppet members
    //    ("@whatsapp_<number>:server"), which may not be loaded yet. This is
    //    what was letting WhatsApp groups slip through and linger.
    final portalRooms = <String>{};
    final joined = client.rooms
        .where((r) =>
            (r.membership == Membership.join ||
                r.membership == Membership.invite) &&
            !r.isSpace)
        .toList();

    // Pass 1 — cheap classification (m.bridge state, names, room ids).
    final unresolved = <Room>[];
    for (final room in joined) {
      final net = BridgeRoomClassifier.getNetworkForRoom(room, client: client);
      if (net == networkId) {
        portalRooms.add(room.id);
      } else if (net == null) {
        unresolved.add(room);
      }
    }

    // Pass 2 — for anything still unknown, load members IN PARALLEL (bounded)
    // so mautrix group portals identifiable only by their "@whatsapp_<n>"
    // puppet members get recognised. Parallel + timeout keeps this quick even
    // with many rooms.
    final toLoad = unresolved.take(150).toList();
    await Future.wait(toLoad.map((room) async {
      try {
        await room.requestParticipants().timeout(const Duration(seconds: 4));
      } catch (_) {}
    }));
    for (final room in toLoad) {
      BridgeRoomClassifier.forget(room.id);
      if (BridgeRoomClassifier.getNetworkForRoom(room, client: client) ==
          networkId) {
        portalRooms.add(room.id);
      }
    }
    final portalList = portalRooms.toList();

    // 4. Local cleanup.
    BridgeRoomClassifier.clearCacheForNetwork(networkId);
    onRoomsForgotten?.call(portalList);

    // 5a. GUARANTEED HIDE: record these rooms as hidden-while-disconnected so
    //     they vanish from the inbox instantly and stay gone across restarts
    //     — even if the leave+forget below never completes. Reconnecting the
    //     network clears this.
    await HiddenRoomsStore.hide(networkId, portalList);

    // 5b. Best-effort real removal (leave + forget) in the background.
    await RoomWipeService.enqueue(client, portalList);

    return DisconnectResult(
      remoteLogoutSent: remoteLogoutSent,
      roomsWiped: portalList.length,
    );
  }

  /// The bridge bot's 1:1 control room. Located, in order of reliability:
  ///   1. the DM whose partner equals the bot MXID the bridge advertises in
  ///      its own portal `m.bridge` state (the real bot, whatever it runs
  ///      as),
  ///   2. the DM matching the guessed "@<alias>bot:server" MXID,
  ///   3. a room named like the bridge control room.
  static Room? findManagementRoom(Client client, NetworkId networkId) {
    final meta = metaFor(networkId);

    final candidateBots = <String>{};
    final discovered = BridgeRoomClassifier.findBridgeBotMxid(client, networkId);
    if (discovered != null) candidateBots.add(discovered.toLowerCase());
    final userDomain = client.userID?.split(':').last;
    if (userDomain != null) {
      candidateBots.add(meta.botMxid(userDomain).toLowerCase());
    }

    for (final room in client.rooms) {
      final dm = (room.directChatMatrixID ?? '').toLowerCase();
      if (dm.isNotEmpty && candidateBots.contains(dm)) return room;
    }

    // Fallback: a DM whose only other member is a "<alias>bot" account, even
    // if directChatMatrixID isn't set; then name-based heuristics.
    for (final room in client.rooms) {
      final dm = (room.directChatMatrixID ?? '').toLowerCase();
      final localpart =
          dm.startsWith('@') ? dm.substring(1).split(':').first : dm;
      if (localpart == '${meta.botAlias}bot') return room;
    }
    for (final room in client.rooms) {
      final name = room.displayname.toLowerCase().trim();
      if (name == meta.botAlias ||
          name == '${meta.botAlias} bridge bot' ||
          name == '${meta.botAlias}bot') {
        return room;
      }
    }
    return null;
  }

  /// Full Allora sign-out: stops every worker, revokes the Matrix session,
  /// clears Supabase auth and every local cache. Chat prefs and settings
  /// stay on-device (they contain no credentials) so a returning user keeps
  /// their appearance/privacy choices.
  static Future<void> logoutAllora(Client client) async {
    // Stop live machinery first so nothing writes during teardown.
    ConnectionManager.instance?.shutdown();
    await RoomWipeService.clearQueue();
    for (final id in NetworkId.values) {
      await HiddenRoomsStore.clear(id);
    }

    for (final id in NetworkId.values) {
      await NetworkConnectionCache.markDisconnected(id, suppressMs: 0);
    }
    BridgeRoomClassifier.clearCache();

    try {
      if (client.isLogged()) await client.logout();
    } catch (e) {
      debugPrint('AccountLifecycle: matrix logout failed: $e');
    }
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      debugPrint('AccountLifecycle: supabase signOut failed: $e');
    }
  }
}

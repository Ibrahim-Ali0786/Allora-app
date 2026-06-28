// ignore_for_file: curly_braces_in_flow_control_structures, deprecated_member_use
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../networks/network_meta.dart';
import '../networks/network_connection_cache.dart';
import '../bridge/bridge_room_classifier.dart';

class WhatsAppDisconnectService {
  WhatsAppDisconnectService._();

  static const _prefsKey = 'wa_pending_wipe_rooms_v1';
  static final ValueNotifier<bool> isWipePendingNotifier = ValueNotifier(false);

  static Future<void> beginDisconnect(Client client) async {
    await NetworkConnectionCache.markDisconnected(NetworkId.whatsapp);
    BridgeRoomClassifier.clearCacheForNetwork(NetworkId.whatsapp);

    final botRoom = _findBotRoom(client);
    if (botRoom != null) {
      await _sendLogoutCommand(botRoom);
    }

    final waRooms = client.rooms
        .where((r) =>
            r.membership == Membership.join &&
            BridgeRoomClassifier.isRoomForNetwork(r, NetworkId.whatsapp,
                client: client))
        .map((r) => r.id)
        .toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, waRooms);

    if (waRooms.isNotEmpty) {
      isWipePendingNotifier.value = true;

      // DISPATCH TO OS!
      Workmanager().registerOneOffTask(
        "whatsapp_wipe_job_${DateTime.now().millisecondsSinceEpoch}",
        "whatsapp_room_wipe_task",
        constraints: Constraints(networkType: NetworkType.connected),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 5),
      );
    } else {
      isWipePendingNotifier.value = false;
    }
  }

  static Future<void> resumePendingWipes(Client client) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      isWipePendingNotifier.value = true;
      // OS handles the wiping, we just update the UI state.
    }
  }

  static Room? _findBotRoom(Client client) {
    final userDomain = client.userID?.split(':').last;
    if (userDomain != null) {
      final botMxid =
          metaFor(NetworkId.whatsapp).botMxid(userDomain).toLowerCase();
      for (final room in client.rooms) {
        if ((room.directChatMatrixID ?? '').toLowerCase() == botMxid)
          return room;
      }
    }
    return null;
  }

  static Future<void> _sendLogoutCommand(Room botRoom) async {
    try {
      // Enterprise Fix: Send 'logout' directly. If we are in the DM,
      // the bot intercepts this and officially unlinks the WhatsApp session.
      await botRoom.sendTextEvent('logout');

      // Give the bridge 2 seconds to process the unlink before we leave the room
      await Future.delayed(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('⚠️ Logout command failed, local cleanup proceeding: $e');
    }
  }

  static bool isWhatsAppRoom(Room room, {Client? client}) =>
      BridgeRoomClassifier.isRoomForNetwork(room, NetworkId.whatsapp,
          client: client);

  /// Enterprise-grade check to strictly identify the management (bot) room
  static bool isManagementRoom(Room room) {
    // The Room object inherently holds a reference to its Client in the Matrix SDK
    final userDomain = room.client.userID?.split(':').last;
    if (userDomain == null) return false;

    // Fetch the exact bot MXID from the central meta file
    final botMxid =
        metaFor(NetworkId.whatsapp).botMxid(userDomain).toLowerCase();

    // Compare the room's direct chat ID to the expected bot MXID
    return (room.directChatMatrixID ?? '').toLowerCase() == botMxid;
  }

  static Future<bool> isWipePending() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_prefsKey) ?? []).isNotEmpty;
  }
}

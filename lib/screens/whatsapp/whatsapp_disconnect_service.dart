import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import '../../data/services/account_lifecycle.dart';
import '../../data/services/room_wipe_service.dart';
import '../bridge/bridge_room_classifier.dart';
import '../networks/network_meta.dart';

/// Thin WhatsApp-flavoured facade over the unified account lifecycle.
///
/// Historically WhatsApp had its own bespoke disconnect path (and was the
/// only network with one). All logic now lives in [AccountLifecycleService]
/// + [RoomWipeService], shared by every network; this class only remains so
/// existing call-sites keep compiling.
class WhatsAppDisconnectService {
  WhatsAppDisconnectService._();

  /// True while *any* wipe is still draining. Kept as a [ValueNotifier] for
  /// the legacy listener in NetworkNotifier.
  static final ValueNotifier<bool> isWipePendingNotifier = ValueNotifier(false);

  static bool _bridged = false;

  /// Wire [isWipePendingNotifier] to the unified pending-set. Idempotent.
  static void ensureBridged() {
    if (_bridged) return;
    _bridged = true;
    RoomWipeService.pending.addListener(() {
      isWipePendingNotifier.value = RoomWipeService.pending.value.isNotEmpty;
    });
    isWipePendingNotifier.value = RoomWipeService.pending.value.isNotEmpty;
  }

  static Future<DisconnectResult> beginDisconnect(Client client) {
    ensureBridged();
    return AccountLifecycleService.disconnectNetwork(client, NetworkId.whatsapp);
  }

  static Future<void> resumePendingWipes(Client client) async {
    ensureBridged();
    await RoomWipeService.resume(client);
  }

  static bool isWhatsAppRoom(Room room, {Client? client}) =>
      BridgeRoomClassifier.isRoomForNetwork(room, NetworkId.whatsapp,
          client: client);

  /// Strict management (bot control) room check via exact bot MXID.
  static bool isManagementRoom(Room room) {
    final userDomain = room.client.userID?.split(':').last;
    if (userDomain == null) return false;
    final botMxid =
        metaFor(NetworkId.whatsapp).botMxid(userDomain).toLowerCase();
    return (room.directChatMatrixID ?? '').toLowerCase() == botMxid;
  }

  static Future<bool> isWipePending() async =>
      RoomWipeService.pending.value.isNotEmpty;
}

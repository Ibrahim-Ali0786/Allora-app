// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

const String kWipeRoomsTask = "whatsapp_room_wipe_task";
const String kPendingRoomsKey = "wa_pending_wipe_rooms_v1"; // Match exactly!

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != kWipeRoomsTask) return Future.value(true);

    debugPrint('[Background Task] OS woke up Allora to wipe rooms.');

    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> pendingRooms = prefs.getStringList(kPendingRoomsKey) ?? [];

      if (pendingRooms.isEmpty) return Future.value(true);

      // Initialize the Database exactly like main.dart
      final dir = await getApplicationSupportDirectory();
      final dbPath = join(dir.path, 'allora_matrix.db');
      final sqliteDb = await openDatabase(dbPath);

      final matrixDb =
          await MatrixSdkDatabase.init('allora_matrix', database: sqliteDb);
      final client = Client('AlloraClient', database: matrixDb);
      await client.init();

      if (client.onLoginStateChanged.value != LoginState.loggedIn) {
        return Future.value(false); // Yield and retry later
      }

      bool madeProgress = false;
      List<String> remainingRooms = List.from(pendingRooms);

      for (final roomId in pendingRooms) {
        final room = client.getRoomById(roomId);
        if (room == null) {
          remainingRooms.remove(roomId);
          continue;
        }

        try {
          if (room.membership == Membership.join) await room.leave();
          await room.forget();

          remainingRooms.remove(roomId);
          madeProgress = true;
          debugPrint('[Background Task] ✓ Removed $roomId');

          await prefs.setStringList(kPendingRoomsKey, remainingRooms);
          await Future.delayed(const Duration(milliseconds: 300));
        } on MatrixException catch (e) {
          if (e.errcode == 'M_LIMIT_EXCEEDED') break; // Yield to OS
        } catch (e) {
          debugPrint('[Background Task] ✗ Error on $roomId: $e');
        }
      }

      if (remainingRooms.isEmpty) return Future.value(true);
      return Future.value(false);
    } catch (err) {
      debugPrint('[Background Task] Fatal Error: $err');
      return Future.value(false);
    }
  });
}

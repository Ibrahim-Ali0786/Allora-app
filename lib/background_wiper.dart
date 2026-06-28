// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

// The unique name for our task
const String kWipeRoomsTask = "whatsapp_room_wipe_task";
const String kPendingRoomsKey = "pending_wipe_rooms";

/// This is the entry point for the OS. It MUST be a top-level function.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != kWipeRoomsTask) return Future.value(true);

    debugPrint('[Background Task] OS woke up Allora to wipe rooms.');

    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> pendingRooms = prefs.getStringList(kPendingRoomsKey) ?? [];

      if (pendingRooms.isEmpty) {
        debugPrint('[Background Task] No rooms left to wipe. Exiting.');
        return Future.value(true); // Tell OS we are done
      }

      // 1. Initialize the Matrix Database exactly like main.dart
      // This is critical so the background task restores your active session!
      final dbPath = join(await getDatabasesPath(), 'allora_matrix.db');
      final sqliteDb = await openDatabase(dbPath);

      final matrixDb = await MatrixSdkDatabase.init(
        'allora_matrix',
        database: sqliteDb,
      );

      // 2. Initialize the Client with the database
      final client = Client(
        'AlloraClient',
        database: matrixDb,
      );

      await client.init();

      // 3. Check login state using the updated syntax
      if (client.onLoginStateChanged.value != LoginState.loggedIn) {
        debugPrint('[Background Task] Client not logged in. Cannot proceed.');
        // Return false so the OS tries again later
        return Future.value(false);
      }

      // 4. Process the queue
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

          // Save progress immediately in case OS kills us mid-loop
          await prefs.setStringList(kPendingRoomsKey, remainingRooms);

          // Matrix rate limit buffer
          await Future.delayed(const Duration(milliseconds: 300));
        } on MatrixException catch (e) {
          if (e.errcode == 'M_LIMIT_EXCEEDED') {
            debugPrint('[Background Task] ⏳ Rate-limited. Yielding to OS.');
            // We hit a hard limit. Stop the loop, tell OS to try again later.
            break;
          }
        } catch (e) {
          debugPrint('[Background Task] ✗ Error on $roomId: $e');
        }
      }

      // 5. Evaluate results
      if (remainingRooms.isEmpty) {
        debugPrint('[Background Task] All rooms wiped successfully.');
        return Future.value(true); // Total success
      } else if (madeProgress) {
        debugPrint(
            '[Background Task] Made progress, but more rooms remain. Yielding.');
        return Future.value(
            false); // Yield so Workmanager reschedules us to finish the job
      } else {
        debugPrint('[Background Task] Failed to make progress. Yielding.');
        return Future.value(false);
      }
    } catch (err) {
      debugPrint('[Background Task] Fatal Error: $err');
      return Future.value(false); // Retry later
    }
  });
}

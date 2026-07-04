import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workmanager/workmanager.dart';

/// Background (killed-app) fallback executor.
///
/// The app performs room wipes and scheduled sends in the foreground the
/// moment they're requested; these tasks only finish whatever a process
/// death interrupted. Both drain the same persisted queues the foreground
/// services use, so work is never done twice and never lost.
const String kWipeRoomsTask = 'allora_room_wipe_task';
const String kLegacyWipeTask = 'whatsapp_room_wipe_task';
const String kScheduledSendTask = 'allora_scheduled_send_task';

const String kWipeKey = 'allora_pending_wipe_rooms_v1';
const String kLegacyWipeKey = 'wa_pending_wipe_rooms_v1';
const String kScheduledKey = 'allora_scheduled_messages_v1';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      if (task == kWipeRoomsTask || task == kLegacyWipeTask) {
        return await _runWipe();
      }
      if (task == kScheduledSendTask) {
        return await _runScheduledSend();
      }
      return true; // unknown/stale task — don't retry forever
    } catch (err) {
      debugPrint('[Background] fatal: $err');
      return false;
    }
  });
}

Future<Client?> _initClient() async {
  final dir = await getApplicationSupportDirectory();
  final dbPath = join(dir.path, 'allora_matrix.db');
  final sqliteDb = await openDatabase(dbPath);
  final matrixDb =
      await MatrixSdkDatabase.init('allora_matrix', database: sqliteDb);
  final client = Client('AlloraClient', database: matrixDb);
  await client.init();
  if (client.onLoginStateChanged.value != LoginState.loggedIn) return null;
  return client;
}

Future<bool> _runWipe() async {
  final prefs = await SharedPreferences.getInstance();
  final pending = <String>{
    ...prefs.getStringList(kWipeKey) ?? const [],
    ...prefs.getStringList(kLegacyWipeKey) ?? const [],
  };
  if (pending.isEmpty) return true;

  final client = await _initClient();
  if (client == null) return false; // retry when logged in

  final remaining = pending.toList();
  for (final roomId in pending) {
    final room = client.getRoomById(roomId);
    if (room == null) {
      remaining.remove(roomId);
      await prefs.setStringList(kWipeKey, remaining);
      continue;
    }
    try {
      if (room.membership == Membership.join ||
          room.membership == Membership.invite) {
        await room.leave();
      }
      await room.forget();
      remaining.remove(roomId);
      await prefs.setStringList(kWipeKey, remaining);
      await prefs.remove(kLegacyWipeKey);
      await Future.delayed(const Duration(milliseconds: 300));
    } on MatrixException catch (e) {
      if (e.errcode == 'M_LIMIT_EXCEEDED') break; // yield; OS retries
      remaining.remove(roomId); // unrecoverable for this room — drop it
      await prefs.setStringList(kWipeKey, remaining);
    } catch (e) {
      debugPrint('[Background] wipe error on $roomId: $e');
    }
  }
  return remaining.isEmpty;
}

Future<bool> _runScheduledSend() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kScheduledKey);
  if (raw == null || raw.isEmpty) return true;

  List<Map<String, dynamic>> queue;
  try {
    queue = (jsonDecode(raw) as List)
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  } catch (_) {
    return true; // corrupt queue — nothing sensible to retry
  }

  final now = DateTime.now().millisecondsSinceEpoch;
  final due = queue.where((m) => (m['sendAtMs'] as int? ?? 0) <= now).toList();
  if (due.isEmpty) return true;

  final client = await _initClient();
  if (client == null) return false;

  var changed = false;
  for (final msg in due) {
    final room = client.getRoomById(msg['roomId'] as String? ?? '');
    if (room == null) {
      queue.remove(msg);
      changed = true;
      continue;
    }
    try {
      await room.sendTextEvent(msg['body'] as String? ?? '');
      queue.remove(msg);
      changed = true;
    } catch (e) {
      debugPrint('[Background] scheduled send failed: $e');
    }
  }
  if (changed) await prefs.setString(kScheduledKey, jsonEncode(queue));
  return queue.every((m) => (m['sendAtMs'] as int? ?? 0) > now);
}

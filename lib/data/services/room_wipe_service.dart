import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../screens/bridge/bridge_room_classifier.dart';

/// Removes bridge portal rooms the moment an account is disconnected.
///
/// Design goals (this is the fix for "WhatsApp groups stay after logout"):
///  1. **Instant UI** — room ids enter [pending] synchronously, so every
///     list/provider that subtracts the pending set updates in the same
///     frame the user taps Disconnect. No restart, no refresh.
///  2. **Foreground-first** — leave+forget runs immediately in-process.
///     The Workmanager job is only a crash/kill *fallback*, not the primary
///     path (previously it was the only path, which meant rooms lingered
///     until Android felt like running the task).
///  3. **Resumable** — the pending set is persisted; whatever survives an
///     app kill is finished by the background task or the next launch.
class RoomWipeService {
  RoomWipeService._();

  /// New generalized key (all networks). The legacy WhatsApp-only key is
  /// still drained by the background task for upgrade safety.
  static const prefsKey = 'allora_pending_wipe_rooms_v1';
  static const legacyPrefsKey = 'wa_pending_wipe_rooms_v1';
  static const taskName = 'allora_room_wipe_task';

  static final ValueNotifier<Set<String>> pending = ValueNotifier(<String>{});

  static bool _running = false;

  static bool get isWiping => pending.value.isNotEmpty;

  /// Hydrate the pending set and finish any interrupted wipe. Call once on
  /// startup after the client is initialized.
  static Future<void> resume(Client client) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = <String>{
      ...prefs.getStringList(prefsKey) ?? const [],
      ...prefs.getStringList(legacyPrefsKey) ?? const [],
    };
    if (ids.isEmpty) return;
    pending.value = ids;
    unawaited(_drain(client));
  }

  /// Queue [roomIds] for removal and start wiping right away.
  static Future<void> enqueue(Client client, List<String> roomIds) async {
    if (roomIds.isEmpty) return;
    pending.value = {...pending.value, ...roomIds};
    await _persist();

    // Crash-safety net: if the process dies mid-wipe the OS finishes it.
    try {
      Workmanager().registerOneOffTask(
        '${taskName}_${DateTime.now().millisecondsSinceEpoch}',
        taskName,
        constraints: Constraints(networkType: NetworkType.connected),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 5),
      );
    } catch (e) {
      debugPrint('RoomWipe: workmanager scheduling failed ($e) — '
          'foreground wipe continues regardless.');
    }

    unawaited(_drain(client));
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(prefsKey, pending.value.toList());
    // Legacy key is superseded — fold anything left in it into the new key.
    await prefs.remove(legacyPrefsKey);
  }

  /// Foreground worker. Single-flight; safe to call repeatedly.
  static Future<void> _drain(Client client) async {
    if (_running) return;
    _running = true;
    var backoff = const Duration(seconds: 2);

    try {
      while (pending.value.isNotEmpty) {
        final id = pending.value.first;
        final room = client.getRoomById(id);

        if (room == null) {
          await _markDone(id);
          continue;
        }

        try {
          if (room.membership == Membership.join ||
              room.membership == Membership.invite) {
            await room.leave();
          }
          await room.forget();
          await _markDone(id);
          backoff = const Duration(seconds: 2);
          // Small spacing keeps Synapse's rate limiter comfortable.
          await Future.delayed(const Duration(milliseconds: 250));
        } on MatrixException catch (e) {
          if (e.errcode == 'M_LIMIT_EXCEEDED') {
            await Future.delayed(backoff);
            backoff *= 2;
            if (backoff > const Duration(seconds: 32)) {
              // Server is very unhappy — let the background task take over.
              break;
            }
          } else if (e.errcode == 'M_FORBIDDEN' || e.errcode == 'M_NOT_FOUND') {
            // Can't leave (already gone / never joined) — treat as done.
            await _markDone(id);
          } else {
            debugPrint('RoomWipe: $id failed: ${e.errcode}');
            await _markDone(id); // don't wedge the queue on odd errors
          }
        } catch (e) {
          debugPrint('RoomWipe: network error on $id: $e — retrying later');
          await Future.delayed(backoff);
          backoff *= 2;
          if (backoff > const Duration(seconds: 32)) break;
        }
      }
    } finally {
      _running = false;
    }
  }

  static Future<void> _markDone(String roomId) async {
    BridgeRoomClassifier.forget(roomId);
    final next = Set<String>.from(pending.value)..remove(roomId);
    pending.value = next;
    await _persist();
  }

  /// Drop the queue entirely (used after a full Allora logout, where the
  /// Matrix account itself is being abandoned).
  static Future<void> clearQueue() async {
    pending.value = <String>{};
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
    await prefs.remove(legacyPrefsKey);
  }
}

/// Riverpod bridge so widgets rebuild the instant the pending set changes.
class WipePendingNotifier extends StateNotifier<Set<String>> {
  WipePendingNotifier() : super(RoomWipeService.pending.value) {
    RoomWipeService.pending.addListener(_onChange);
  }

  void _onChange() => state = RoomWipeService.pending.value;

  @override
  void dispose() {
    RoomWipeService.pending.removeListener(_onChange);
    super.dispose();
  }
}

final wipePendingProvider =
    StateNotifierProvider<WipePendingNotifier, Set<String>>(
        (ref) => WipePendingNotifier());

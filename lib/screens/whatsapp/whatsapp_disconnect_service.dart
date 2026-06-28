// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../networks/network_meta.dart';
import '../networks/network_connection_cache.dart';
import '../bridge/bridge_room_classifier.dart';

/// Manages the full WhatsApp disconnect lifecycle:
/// 1. Sends a logout command to the bridge bot immediately.
/// 2. Marks the cache as disconnected — *stickily*, see
///    [NetworkConnectionCache] — so nothing routine can flip it back to
///    Connected no matter how long step 3 takes or how many times the app
///    is restarted before it finishes.
/// 3. Collects every WhatsApp portal room and leaves/forgets them one by
///    one in the background, persisting progress to disk after every
///    single change. If the app is killed or backgrounded mid-wipe, calling
///    [resumePendingWipes] on the next launch picks up exactly where it
///    left off instead of leaving orphaned rooms (and their data) on the
///    server forever — this is the fix for "the groups are still there".
///
/// The `isWipePendingNotifier` flag lets the ChatListScreen hide WhatsApp
/// rooms instantly (before Matrix propagates the leaves), and the
/// ConnectNetworksScreen show a spinner while clearing.
class WhatsAppDisconnectService {
  WhatsAppDisconnectService._();

  static const _prefsKey = 'wa_pending_wipe_rooms_v1';

  /// How many times we'll retry a single stuck room within one app
  /// session before deferring it to the next session. It stays in the
  /// *persisted* queue regardless — this only stops one bad room from
  /// blocking everything else in a tight retry loop right now.
  static const _maxAttemptsPerSession = 5;

  // ── PUBLIC STATE ──────────────────────────────────────────────────────────

  /// True while we are still in the process of leaving/forgetting rooms
  /// (including rooms left over from a previous, interrupted session).
  static final ValueNotifier<bool> isWipePendingNotifier = ValueNotifier(false);

  // ── WIPE QUEUE ────────────────────────────────────────────────────────────

  static final Set<String> _pendingRoomIds = {};
  static final Map<String, int> _sessionAttempts = {};
  static bool _wiperRunning = false;
  static bool _loadedFromDisk = false;

  // ── ENTRY POINT ───────────────────────────────────────────────────────────

  /// Call this when the user confirms disconnect. Sends the logout command,
  /// updates the cache immediately, then schedules room cleanup.
  static Future<void> beginDisconnect(Client client) async {
    // 1. Mark disconnected in cache. This is now sticky (see
    //    NetworkConnectionCache) — no routine probe can undo it, no matter
    //    how long the wipe below takes or how many app restarts happen
    //    before it finishes.
    await NetworkConnectionCache.markDisconnected(NetworkId.whatsapp);

    // 1b. Clear the room classifier cache to force fresh identification
    BridgeRoomClassifier.clearCacheForNetwork(NetworkId.whatsapp);

    // 2. Send logout to the bridge bot, found via the canonical (exact
    //    bot-mxid) check first. The old display-name-only matching here
    //    could miss the room entirely (skipping the logout silently — the
    //    WhatsApp account would stay logged in server-side) or, worse,
    //    match the *wrong* room. This is also the same check used below to
    //    make sure we never accidentally queue the management room itself
    //    for wiping.
    final botRoom = _findBotRoom(client);
    if (botRoom != null) {
      await _sendLogoutCommand(botRoom);
    }

    // 3. Collect all WhatsApp portal rooms via the SAME classifier the chat
    //    list uses to decide what counts as "a WhatsApp room". Using one
    //    shared source of truth means a room can never be hidden from the
    //    inbox without also being queued for wiping, or vice versa — that
    //    mismatch was a real way for rooms to silently survive disconnect.
    final waRooms = client.rooms
        .where((r) =>
            r.membership == Membership.join &&
            BridgeRoomClassifier.isRoomForNetwork(r, NetworkId.whatsapp,
                client: client))
        .map((r) => r.id)
        .toSet();

    await _addToPendingQueue(waRooms);

    // 4. Signal the UI immediately.
    isWipePendingNotifier.value = true;

    // 5. Start the background wiper if not already running.
    _startWiper(client);
  }

  /// Call this once, early, whenever you have a logged-in [Client] — e.g.
  /// from `ChatListScreen.initState` and `ConnectNetworksScreen.initState`.
  /// It's cheap and idempotent: if nothing is pending it does nothing; if a
  /// previous disconnect was interrupted by the app being closed or killed
  /// mid-wipe, this resumes the cleanup immediately instead of leaving
  /// those rooms (and the data behind them) on the server indefinitely.
  static Future<void> resumePendingWipes(Client client) async {
    await _loadFromDisk();
    if (_pendingRoomIds.isEmpty) return;

    // Clear cache to ensure fresh state for pending wipes
    BridgeRoomClassifier.clearCacheForNetwork(NetworkId.whatsapp);

    isWipePendingNotifier.value = true;
    _startWiper(client);
  }

  // ── PERSISTENCE ───────────────────────────────────────────────────────────

  static Future<void> _loadFromDisk() async {
    if (_loadedFromDisk) return;
    _loadedFromDisk = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefsKey);
      if (raw != null) _pendingRoomIds.addAll(raw);
    } catch (_) {
      // Corrupt/missing prefs — nothing to resume, which is fine.
    }
  }

  static Future<void> _persistPendingQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, _pendingRoomIds.toList());
    } catch (_) {
      // Worst case we just re-discover the same rooms next time
      // beginDisconnect runs, which is harmless.
    }
  }

  static Future<void> _addToPendingQueue(Set<String> ids) async {
    await _loadFromDisk();
    _pendingRoomIds.addAll(ids);
    await _persistPendingQueue();
  }

  // ── WIPER ─────────────────────────────────────────────────────────────────

  static void _startWiper(Client client) {
    if (_wiperRunning) return;
    _wiperRunning = true;

    Future.microtask(() async {
      // Rooms that have hit the per-session retry cap. Kept separate from
      // _pendingRoomIds (which stays persisted) so one permanently-failing
      // room can't block the rest of the queue in a tight loop forever —
      // it'll get a fresh set of attempts next time resumePendingWipes runs.
      final deferredThisSession = <String>{};

      while (true) {
        final id = _pendingRoomIds.firstWhere(
          (r) => !deferredThisSession.contains(r),
          orElse: () => '',
        );
        if (id.isEmpty) break; // Nothing left we can usefully retry right now.

        var removed = false;
        try {
          final room = client.getRoomById(id);
          if (room == null) {
            // Already gone locally — nothing left to clean up server-side.
            removed = true;
          } else {
            // Leave first, then forget — correct Matrix sequence.
            if (room.membership == Membership.join) {
              await room.leave();
            }
            await client.forgetRoom(id);
            removed = true;
          }
        } on MatrixException catch (e) {
          // These error codes mean "you're already not meaningfully in
          // this room" from the server's point of view — that's success,
          // not failure, so don't keep retrying it.
          const alreadyGoneCodes = {'M_NOT_FOUND', 'M_FORBIDDEN', 'M_UNKNOWN'};
          removed = alreadyGoneCodes.contains(e.errcode);
        } catch (_) {
          // Network hiccup, timeout, etc. Leave `removed` false so this
          // room gets retried — either later in this loop or next launch.
          // This is the important change from the old version, which
          // swallowed *every* exception here and silently dropped the room
          // from the queue, leaving it joined forever if e.g. the
          // homeserver rate-limited a burst of leave/forget calls.
        }

        if (removed) {
          _pendingRoomIds.remove(id);
          _sessionAttempts.remove(id);
          BridgeRoomClassifier.forget(id);
          await _persistPendingQueue();
        } else {
          final attempts = (_sessionAttempts[id] ?? 0) + 1;
          _sessionAttempts[id] = attempts;
          if (attempts >= _maxAttemptsPerSession) {
            deferredThisSession.add(id);
          }
        }

        // Small yield so we don't starve the event loop or hammer the
        // homeserver with a tight loop.
        await Future.delayed(const Duration(milliseconds: 120));
      }

      _wiperRunning = false;
      // If anything got deferred, it's still sitting in the persisted
      // queue, so keep reporting "pending" honestly rather than claiming
      // we're fully done.
      isWipePendingNotifier.value = _pendingRoomIds.isNotEmpty;
    });
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  static Room? _findBotRoom(Client client) {
    final userDomain = client.userID?.split(':').last;
    if (userDomain != null) {
      final botMxid =
          metaFor(NetworkId.whatsapp).botMxid(userDomain).toLowerCase();
      for (final room in client.rooms) {
        if ((room.directChatMatrixID ?? '').toLowerCase() == botMxid) {
          return room;
        }
      }
    }
    // Fallback heuristic, kept for resilience in case the mxid check above
    // doesn't match for some unusual bot setup.
    for (final room in client.rooms) {
      final name = room.displayname.toLowerCase();
      if (name == 'whatsapp' ||
          name == 'whatsapp bridge bot' ||
          name.contains('whatsapp bridge')) {
        return room;
      }
    }
    return null;
  }

  /// Sends logout command to WhatsApp bridge with retry logic to ensure
  /// the message reaches the bot and propagates to WhatsApp servers.
  static Future<void> _sendLogoutCommand(Room botRoom,
      {int maxRetries = 2}) async {
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        await botRoom.sendTextEvent('!wa logout');
        debugPrint(
            '✅ WhatsApp logout command sent (attempt ${attempt + 1}/${maxRetries + 1})');
        return; // Success, exit
      } catch (e) {
        debugPrint('⚠️  Logout attempt ${attempt + 1} failed: $e');
        if (attempt < maxRetries) {
          // Wait a bit before retry to allow bridge to recover
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        }
      }
    }

    // If all retries failed, log but continue anyway — the local room wipe
    // below still clears WhatsApp out of this app's inbox, and the cache
    // stays disconnected regardless. The bridge may eventually process
    // the logout asynchronously or on next sync.
    debugPrint(
        '⚠️  WhatsApp logout command failed after ${maxRetries + 1} attempts. Local cleanup will proceed.');
  }

  /// Kept so any other code can still ask "is this a WhatsApp room?"
  /// directly. Delegates to the shared classifier so this can never drift
  /// out of sync with what the chat list considers a WhatsApp room — that
  /// drift was a real way for rooms to be hidden from the inbox without
  /// ever actually being queued for wiping (or vice versa).
  static bool isWhatsAppRoom(Room room, {Client? client}) =>
      BridgeRoomClassifier.isRoomForNetwork(room, NetworkId.whatsapp,
          client: client);

  /// Checks whether there are still pending rooms to wipe (including ones
  /// not yet loaded into memory from a previous session).
  static Future<bool> isWipePending() async {
    await _loadFromDisk();
    return _pendingRoomIds.isNotEmpty || _wiperRunning;
  }

  /// Checks if a room is the WhatsApp management/bridge room (the bot room).
  static bool isManagementRoom(Room room) {
    // Check if this room's direct chat partner is the WhatsApp bot
    final botRoom = room.membership == Membership.join &&
        (room.directChatMatrixID?.toLowerCase().contains('whatsapp') ?? false);
    if (botRoom) return true;

    // Fallback: check display name
    final name = room.displayname.toLowerCase();
    return name == 'whatsapp' ||
        name == 'whatsapp bridge bot' ||
        name.contains('whatsapp bridge');
  }
}

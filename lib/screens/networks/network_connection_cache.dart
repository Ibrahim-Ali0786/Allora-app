import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'network_meta.dart';

class NetworkStatusSnapshot {
  final bool connected;
  final String? accountLabel;
  final String? lastSynced;

  /// Epoch-ms timestamp of last real status write. 0 = "never checked".
  final int updatedAt;

  /// True once the user has explicitly disconnected this network from
  /// *this app* and it hasn't been explicitly reconnected since.
  ///
  /// This replaces the old time-based suppression window, which was the
  /// root cause of "shows Connected again after a restart": that design
  /// used a 60s timer to stop a lagging bridge-bot reply from re-connecting
  /// a just-disconnected account, but if the bridge bot's logout (or the
  /// room wipe) was still in flight when that timer expired, the next
  /// routine `list-logins` probe would see "still logged in" and flip the
  /// cache straight back to Connected — including across app restarts,
  /// since the stored timestamp doesn't pause while the app is closed.
  ///
  /// Now there's no clock involved in the gate at all: once this is set,
  /// *no* routine/automatic probe can clear it — only an explicit, confirmed
  /// fresh login (passing `force: true` to [markConnected]) can.
  final bool manuallyDisconnected;

  /// A short, belt-and-suspenders debounce window immediately after
  /// disconnecting, in case an in-flight network response lands a few
  /// hundred ms later. This is no longer the primary guard —
  /// [manuallyDisconnected] is — so it's fine for this to be short, and it
  /// only matters at all if you ever call [markDisconnected] without it
  /// also setting the sticky flag (it always does, but kept for clarity).
  final int suppressAutoDetectUntil;

  const NetworkStatusSnapshot({
    required this.connected,
    this.accountLabel,
    this.lastSynced,
    this.updatedAt = 0,
    this.manuallyDisconnected = false,
    this.suppressAutoDetectUntil = 0,
  });

  factory NetworkStatusSnapshot.unknown() =>
      const NetworkStatusSnapshot(connected: false);

  factory NetworkStatusSnapshot.fromJson(Map<String, dynamic> j) =>
      NetworkStatusSnapshot(
        connected: j['connected'] as bool? ?? false,
        accountLabel: j['accountLabel'] as String?,
        lastSynced: j['lastSynced'] as String?,
        updatedAt: j['updatedAt'] as int? ?? 0,
        manuallyDisconnected: j['manuallyDisconnected'] as bool? ?? false,
        suppressAutoDetectUntil: j['suppressAutoDetectUntil'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'connected': connected,
        'accountLabel': accountLabel,
        'lastSynced': lastSynced,
        'updatedAt': updatedAt,
        'manuallyDisconnected': manuallyDisconnected,
        'suppressAutoDetectUntil': suppressAutoDetectUntil,
      };

  /// True once we have written a real status at least once.
  bool get hasData => updatedAt > 0;

  bool get autoDetectSuppressed =>
      manuallyDisconnected ||
      DateTime.now().millisecondsSinceEpoch < suppressAutoDetectUntil;
}

/// Persists "is network X connected" across app restarts and screen
/// navigations, broadcasting changes instantly to any listener.
///
/// Key invariant: once [markDisconnected] is called, nothing can flip a
/// network back to Connected except an explicit `force: true` call to
/// [markConnected] — i.e. a real, confirmed login event (a pairing code
/// succeeded, an OAuth flow completed), never a routine background probe
/// like a periodic `list-logins` check. That's what makes a manual
/// disconnect "sticky" across restarts, screen changes, and slow/lagging
/// bridge replies.
class NetworkConnectionCache {
  // Bumped from v2 -> v3: old snapshots don't have `manuallyDisconnected`,
  // and fromJson() defaults it to false for any pre-existing entry, which
  // is the safe interpretation (worst case: one extra routine probe before
  // it's stale-disconnected again, never the reverse).
  static const _prefsKey = 'network_connection_cache_v3';
  static bool _hydrated = false;

  static final ValueNotifier<Map<NetworkId, NetworkStatusSnapshot>> notifier =
      ValueNotifier({});

  // ── HYDRATE ───────────────────────────────────────────────────────────────

  /// Call once, as early as possible (ideally in main() before runApp).
  /// After the first call this is a no-op.
  static Future<void> hydrate() async {
    if (_hydrated) return;
    _hydrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final map = <NetworkId, NetworkStatusSnapshot>{};
      for (final entry in decoded.entries) {
        for (final id in NetworkId.values) {
          if (id.name == entry.key) {
            map[id] = NetworkStatusSnapshot.fromJson(
                entry.value as Map<String, dynamic>);
            break;
          }
        }
      }
      notifier.value = map;
    } catch (_) {
      // Corrupt cache — start fresh.
    }
  }

  // ── PERSIST ───────────────────────────────────────────────────────────────

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final asJson = {
      for (final e in notifier.value.entries) e.key.name: e.value.toJson(),
    };
    await prefs.setString(_prefsKey, jsonEncode(asJson));
  }

  // ── READ ──────────────────────────────────────────────────────────────────

  static NetworkStatusSnapshot get(NetworkId id) =>
      notifier.value[id] ?? NetworkStatusSnapshot.unknown();

  // ── WRITE ─────────────────────────────────────────────────────────────────

  /// Records a confirmed live connection.
  ///
  /// Pass [force]: true ONLY from a genuinely confirmed event — e.g. the
  /// bridge bot just replied "logged in" right after you sent a pairing
  /// code, or an OAuth flow just completed. Routine background probes
  /// (a periodic `list-logins` check) must NOT pass force: true, so they
  /// can never silently undo a manual disconnect.
  static Future<void> markConnected(
    NetworkId id, {
    String? accountLabel,
    String? lastSynced,
    bool force = false,
  }) async {
    final current = get(id);

    // 🔒 Suppression guard: do NOT re-connect during cooldown — unless this
    // is a forced, explicitly-confirmed login.
    if (!force && current.autoDetectSuppressed) return;

    final next = Map<NetworkId, NetworkStatusSnapshot>.from(notifier.value);
    next[id] = NetworkStatusSnapshot(
      connected: true,
      accountLabel: accountLabel ?? current.accountLabel,
      lastSynced: lastSynced ?? 'Active',
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      // A confirmed connect always clears any previous manual disconnect.
      manuallyDisconnected: false,
      suppressAutoDetectUntil: 0,
    );
    notifier.value = next;
    await _persist();
  }

  /// Records a confirmed disconnection. This always wins immediately and
  /// sets the sticky [NetworkStatusSnapshot.manuallyDisconnected] flag, so
  /// nothing routine can flip it back regardless of how long any background
  /// cleanup takes or how many times the app is restarted before it
  /// finishes — see the class doc for why that matters.
  static Future<void> markDisconnected(
    NetworkId id, {
    int suppressMs = 60000,
  }) async {
    final next = Map<NetworkId, NetworkStatusSnapshot>.from(notifier.value);
    next[id] = NetworkStatusSnapshot(
      connected: false,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      manuallyDisconnected: true,
      suppressAutoDetectUntil:
          DateTime.now().millisecondsSinceEpoch + suppressMs,
    );
    notifier.value = next;
    await _persist();
  }

  /// Resets a network's cache entry entirely, including the manual-disconnect
  /// flag. Call this right when the user *starts* a brand new connect flow
  /// (e.g. as soon as they tap "Connect" on a previously-disconnected
  /// network), so a stale flag from a previous disconnect can never linger
  /// and so a non-forced `markConnected` works again immediately rather than
  /// waiting for the next forced confirmation.
  static Future<void> clear(NetworkId id) async {
    final next = Map<NetworkId, NetworkStatusSnapshot>.from(notifier.value);
    next.remove(id);
    notifier.value = next;
    await _persist();
  }
}

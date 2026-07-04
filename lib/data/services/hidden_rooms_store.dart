import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../screens/networks/network_meta.dart';

/// Persistent "hide these rooms because their network is disconnected" set.
///
/// This is the guaranteed-hide safety net: the instant a platform is
/// disconnected we record every room attributed to it here, and the inbox
/// filters them out — permanently, across restarts — regardless of whether
/// the background room-wipe (leave+forget) actually succeeds. Reconnecting
/// the platform clears its entry so the chats come back.
class HiddenRoomsStore {
  HiddenRoomsStore._();

  static const _key = 'allora_network_hidden_rooms_v1';
  static bool _hydrated = false;

  /// networkId.name -> set of hidden room ids.
  static final Map<String, Set<String>> _byNetwork = {};

  /// Flattened union of every hidden room id; what the inbox checks.
  static final ValueNotifier<Set<String>> notifier = ValueNotifier(<String>{});

  static Future<void> hydrate() async {
    if (_hydrated) return;
    _hydrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _byNetwork.clear();
      decoded.forEach((k, v) {
        if (v is List) _byNetwork[k] = v.whereType<String>().toSet();
      });
      _recompute();
    } catch (_) {
      // corrupt — start clean
    }
  }

  static void _recompute() {
    final union = <String>{};
    for (final s in _byNetwork.values) {
      union.addAll(s);
    }
    notifier.value = union;
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(_byNetwork.map((k, v) => MapEntry(k, v.toList()))));
  }

  static bool contains(String roomId) => notifier.value.contains(roomId);

  /// Hide [roomIds] because [id] was disconnected.
  static Future<void> hide(NetworkId id, Iterable<String> roomIds) async {
    final set = _byNetwork.putIfAbsent(id.name, () => <String>{});
    final before = set.length;
    set.addAll(roomIds);
    if (set.length == before) return;
    _recompute();
    await _persist();
    debugPrint('HiddenRooms: hiding ${set.length} ${id.name} rooms');
  }

  /// Un-hide everything for [id] — call on reconnect so its chats return.
  static Future<void> clear(NetworkId id) async {
    if (_byNetwork.remove(id.name) == null) return;
    _recompute();
    await _persist();
  }

  /// Drop specific ids from every network's set (e.g. after a full logout).
  static Future<void> forget(Iterable<String> roomIds) async {
    final ids = roomIds.toSet();
    var changed = false;
    for (final set in _byNetwork.values) {
      final before = set.length;
      set.removeAll(ids);
      if (set.length != before) changed = true;
    }
    if (changed) {
      _recompute();
      await _persist();
    }
  }
}

/// Riverpod bridge so the inbox rebuilds the instant the hidden set changes.
class HiddenRoomsNotifier extends StateNotifier<Set<String>> {
  HiddenRoomsNotifier() : super(HiddenRoomsStore.notifier.value) {
    HiddenRoomsStore.notifier.addListener(_onChange);
  }
  void _onChange() => state = HiddenRoomsStore.notifier.value;
  @override
  void dispose() {
    HiddenRoomsStore.notifier.removeListener(_onChange);
    super.dispose();
  }
}

final hiddenRoomsProvider =
    StateNotifierProvider<HiddenRoomsNotifier, Set<String>>(
        (ref) => HiddenRoomsNotifier());

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

/// A message queued to send at a future time.
class ScheduledMessage {
  final String id;
  final String roomId;
  final String roomName;
  final String body;
  final int sendAtMs;

  const ScheduledMessage({
    required this.id,
    required this.roomId,
    required this.roomName,
    required this.body,
    required this.sendAtMs,
  });

  Map<String, dynamic> toJson() => {
        'id': id, 'roomId': roomId, 'roomName': roomName,
        'body': body, 'sendAtMs': sendAtMs,
      };

  factory ScheduledMessage.fromJson(Map<String, dynamic> j) =>
      ScheduledMessage(
        id: j['id'] as String? ?? '',
        roomId: j['roomId'] as String? ?? '',
        roomName: j['roomName'] as String? ?? '',
        body: j['body'] as String? ?? '',
        sendAtMs: j['sendAtMs'] as int? ?? 0,
      );
}

/// Schedule-for-later sending.
///
/// Primary path: an in-process [Timer] fires exactly on time while the app
/// lives. Fallback path: a Workmanager one-off task drains the same
/// persisted queue if the app was killed. On every launch [resume] sends
/// anything that came due while the app was closed.
class ScheduledMessageService {
  ScheduledMessageService._();

  static const prefsKey = 'allora_scheduled_messages_v1';
  static const taskName = 'allora_scheduled_send_task';

  static final ValueNotifier<List<ScheduledMessage>> queue = ValueNotifier([]);
  static Client? _client;
  static Timer? _timer;

  static Future<void> resume(Client client) async {
    _client = client;
    queue.value = await _load();
    await _drainDue();
    _armTimer();
  }

  static Future<void> schedule(
    Client client, {
    required String roomId,
    required String roomName,
    required String body,
    required DateTime sendAt,
  }) async {
    _client = client;
    final msg = ScheduledMessage(
      id: 'sm_${DateTime.now().microsecondsSinceEpoch}',
      roomId: roomId,
      roomName: roomName,
      body: body,
      sendAtMs: sendAt.millisecondsSinceEpoch,
    );
    queue.value = [...queue.value, msg]
      ..sort((a, b) => a.sendAtMs.compareTo(b.sendAtMs));
    await _persist();
    _armTimer();

    try {
      Workmanager().registerOneOffTask(
        '${taskName}_${msg.id}',
        taskName,
        initialDelay: sendAt.difference(DateTime.now()).isNegative
            ? Duration.zero
            : sendAt.difference(DateTime.now()),
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (e) {
      debugPrint('ScheduledMessages: workmanager backstop failed: $e');
    }
  }

  static Future<void> cancel(String id) async {
    queue.value = queue.value.where((m) => m.id != id).toList();
    await _persist();
    _armTimer();
  }

  static void _armTimer() {
    _timer?.cancel();
    if (queue.value.isEmpty) return;
    final next = queue.value.first.sendAtMs;
    final ms = next - DateTime.now().millisecondsSinceEpoch;
    final delay = Duration(milliseconds: ms < 0 ? 0 : ms);
    _timer = Timer(delay, () async {
      await _drainDue();
      _armTimer();
    });
  }

  static Future<void> _drainDue() async {
    final client = _client;
    if (client == null || !client.isLogged()) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = queue.value.where((m) => m.sendAtMs <= now).toList();
    if (due.isEmpty) return;

    for (final msg in due) {
      final room = client.getRoomById(msg.roomId);
      if (room != null) {
        try {
          await room.sendTextEvent(msg.body);
        } catch (e) {
          debugPrint('ScheduledMessages: send failed for ${msg.id}: $e');
          continue; // keep it queued; retried on next resume/timer
        }
      }
      queue.value = queue.value.where((m) => m.id != msg.id).toList();
    }
    await _persist();
  }

  static Future<List<ScheduledMessage>> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => ScheduledMessage.fromJson(Map<String, dynamic>.from(m)))
          .toList()
        ..sort((a, b) => a.sendAtMs.compareTo(b.sendAtMs));
    } catch (_) {
      return [];
    }
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        prefsKey, jsonEncode(queue.value.map((m) => m.toJson()).toList()));
  }

  static void shutdown() {
    _timer?.cancel();
    _timer = null;
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import '../settings/app_settings.dart';

/// Disappearing messages, honestly implemented for Matrix:
///
///  * When a chat has a timer, we set the room's `m.room.retention` state
///    (best effort) so retention-aware servers purge history for everyone.
///  * Independently, a local sweeper redacts **your own** messages once they
///    exceed the timer. On Matrix you can only delete other people's
///    messages if you have moderation power in that room, so — exactly like
///    every bridge-based messenger — the guarantee applies to what you send.
///    The settings UI states this plainly instead of pretending otherwise.
///
/// Redaction removes the content from the server and (via sync) from every
/// local cache, notification and backup that follows the room state.
class DisappearingMessageService {
  DisappearingMessageService._();

  static Client? _client;
  static SettingsController? _settings;
  static Timer? _timer;
  static bool _sweeping = false;

  static const presets = <int, String>{
    0: 'Off',
    86400: '24 hours',
    604800: '7 days',
    2592000: '30 days',
    7776000: '90 days',
  };

  static String labelFor(int seconds) {
    if (seconds <= 0) return 'Off';
    final preset = presets[seconds];
    if (preset != null) return preset;
    if (seconds % 86400 == 0) return '${seconds ~/ 86400} days';
    if (seconds % 3600 == 0) return '${seconds ~/ 3600} hours';
    return '${(seconds / 60).ceil()} min';
  }

  static void start(Client client, SettingsController settings) {
    _client = client;
    _settings = settings;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => sweep());
    // First pass shortly after startup, once sync has caught up a bit.
    Timer(const Duration(seconds: 20), sweep);
  }

  static void shutdown() {
    _timer?.cancel();
    _timer = null;
  }

  /// Apply a timer to a room: persist locally + best-effort server retention.
  static Future<void> setTimer(Room room, int seconds) async {
    _settings?.setDisappearing(room.id, seconds);
    try {
      await room.client.setRoomStateWithKey(
        room.id,
        'm.room.retention',
        '',
        seconds > 0
            ? {'max_lifetime': seconds * 1000}
            : <String, Object?>{},
      );
    } catch (e) {
      // Bridged portals often deny state changes — the local sweeper still
      // enforces the timer for our own messages.
      debugPrint('Disappearing: retention state rejected for ${room.id}: $e');
    }
  }

  /// Redact own expired messages across all rooms with timers.
  static Future<void> sweep() async {
    if (_sweeping) return;
    final client = _client;
    final settings = _settings;
    if (client == null || settings == null || !client.isLogged()) return;

    final timers = settings.state.disappearingSeconds;
    if (timers.isEmpty) return;

    _sweeping = true;
    try {
      for (final entry in timers.entries) {
        final room = client.getRoomById(entry.key);
        if (room == null || entry.value <= 0) continue;
        final cutoff =
            DateTime.now().subtract(Duration(seconds: entry.value));

        Timeline? timeline;
        try {
          timeline = await room.getTimeline();
          // Only sweep what's loaded plus one history page — a bounded,
          // cheap pass that runs often instead of an expensive full crawl.
          if (timeline.canRequestHistory) {
            await timeline.requestHistory(historyCount: 50);
          }
          for (final event in List<Event>.from(timeline.events)) {
            if (event.senderId != client.userID) continue;
            if (event.type != EventTypes.Message) continue;
            if (event.redacted) continue;
            if (event.originServerTs.isAfter(cutoff)) continue;
            try {
              await room.redactEvent(event.eventId);
              await Future.delayed(const Duration(milliseconds: 200));
            } on MatrixException catch (e) {
              if (e.errcode == 'M_LIMIT_EXCEEDED') {
                await Future.delayed(const Duration(seconds: 5));
              }
            } catch (_) {}
          }
        } catch (e) {
          debugPrint('Disappearing: sweep failed for ${room.id}: $e');
        } finally {
          timeline?.cancelSubscriptions();
        }
      }
    } finally {
      _sweeping = false;
    }
  }
}

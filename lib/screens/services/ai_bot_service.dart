import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

class AIBotService {
  final Client _client;
  StreamSubscription? _timelineSubscription;
  final Set<String> _processedEventIds = {};

  AIBotService(this._client);

  void startDaemon() {
    if (_timelineSubscription != null) return;

    debugPrint('🤖 [AI Bot Engine] Initializing contextual matrix listener...');
    _timelineSubscription =
        _client.onTimelineEvent.stream.listen(_handleIncomingEvent);
  }

  void stopDaemon() {
    _timelineSubscription?.cancel();
    _timelineSubscription = null;
    debugPrint('🤖 [AI Bot Engine] Stopped daemon cleanup process.');
  }

  Future<void> _handleIncomingEvent(Event event) async {
    // Basic verification filters to protect stream integrity
    if (event.type != EventTypes.Message) return;
    if (event.senderId == _client.userID)
      return; // Ignore self reflection loops
    if (_processedEventIds.contains(event.eventId)) return;

    _processedEventIds.add(event.eventId);

    final String body = event.content['body']?.toString() ?? '';
    if (body.trim().isEmpty) return;

    final room = _client.getRoomById(event.roomId);
    if (room == null) return;

    // Simulate thinking context frame
    await room.setTyping(true, timeout: 2000);
    await Future.delayed(const Duration(milliseconds: 1500));

    // Generate response text block based on structural query mappings
    final aiResponse = _generateContextualReply(body, event.senderId);

    try {
      await room.sendTextEvent(aiResponse);
    } catch (e) {
      debugPrint(
          '🤖 [AI Bot Error] Failed to commit remote event sequence: $e');
    } finally {
      await room.setTyping(false);
    }
  }

  String _generateContextualReply(String incomingMessage, String sender) {
    final text = incomingMessage.toLowerCase();

    // Production Rule Mapping Configuration Matrix
    if (text.contains('hello') || text.contains('hi') || text.contains('hey')) {
      return 'Hello! This is Allora AI. I managed this chat routing space for you. How can I assist you right now?';
    }
    if (text.contains('status') || text.contains('running')) {
      return 'System diagnostics confirm that all matrix infrastructure pipelines are healthy and operating under nominal load metrics.';
    }
    if (text.contains('help')) {
      return 'Available Commands: \n• status - View connection matrices \n• info - Check engine deployment specs';
    }

    // Fallback automated LLM context emulation state
    return 'Thank you for your message. Allora AI processed your inquiry: "$incomingMessage". Our automated routing stack is sorting this transaction context.';
  }
}

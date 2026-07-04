import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Writing tones supported by rewrite/compose.
enum AiTone {
  professional('Professional', '💼'),
  friendly('Friendly', '😊'),
  romantic('Romantic', '💌'),
  formal('Formal', '🎩'),
  funny('Funny', '😄'),
  shorter('Shorter', '✂️'),
  longer('Longer', '📜');

  final String label;
  final String emoji;
  const AiTone(this.label, this.emoji);
}

/// One line of conversation context sent to the assistant. Only what the
/// user explicitly invokes AI on is ever sent — and only the last few
/// messages, with Matrix IDs stripped, never the whole history.
class AiMessage {
  final String sender;
  final String text;
  const AiMessage({required this.sender, required this.text});

  Map<String, String> toJson() => {'sender': sender, 'text': text};
}

class AiResult {
  final String? text;
  final List<String> suggestions;
  final String? error;

  const AiResult({this.text, this.suggestions = const [], this.error});

  bool get ok => error == null;

  factory AiResult.failure(String message) => AiResult(error: message);
}

/// Client for the `allora-ai` Supabase Edge Function.
///
/// The function holds the LLM API key server-side (never shipped in the
/// APK), verifies the caller's Supabase JWT, and proxies to the model.
/// See `supabase/functions/allora-ai/` in the repo for the deployable
/// source and setup instructions.
class AiService {
  AiService._();

  static const _functionName = 'allora-ai';
  static const _notConfigured =
      'Allora AI is unreachable. Check your connection — or if you are '
      'self-hosting, deploy the allora-ai function (see supabase/functions).';

  /// Hard caps on context payload size.
  static const _maxContextChars = 6000;
  static const _maxContextMessages = 20;

  static Future<AiResult> _invoke(Map<String, dynamic> body) async {
    try {
      final res = await Supabase.instance.client.functions
          .invoke(_functionName, body: body)
          .timeout(const Duration(seconds: 45));
      final data = res.data;
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        if (map['ok'] == true) {
          return AiResult(
            text: map['text'] as String?,
            suggestions:
                (map['suggestions'] as List?)?.whereType<String>().toList() ??
                    const [],
          );
        }
        return AiResult.failure(
            map['error'] as String? ?? 'The AI service returned an error.');
      }
      return AiResult.failure('Unexpected AI service response.');
    } catch (e) {
      debugPrint('AiService: $e');
      return AiResult.failure(_notConfigured);
    }
  }

  // ── Text tools ────────────────────────────────────────────────────────────

  static Future<AiResult> rewrite(String text, AiTone tone) =>
      _invoke({'task': 'rewrite', 'text': text, 'tone': tone.name});

  static Future<AiResult> fixGrammar(String text) =>
      _invoke({'task': 'grammar', 'text': text});

  static Future<AiResult> translate(String text, String language) =>
      _invoke({'task': 'translate', 'text': text, 'language': language});

  static Future<AiResult> explain(String text) =>
      _invoke({'task': 'explain', 'text': text});

  static Future<AiResult> detectTone(String text) =>
      _invoke({'task': 'detect_tone', 'text': text});

  static Future<AiResult> compose(String prompt, {AiTone? tone}) => _invoke({
        'task': 'compose',
        'prompt': prompt,
        if (tone != null) 'tone': tone.name,
      });

  // ── Conversation tools ───────────────────────────────────────────────────

  static Future<AiResult> summarize(List<AiMessage> context) =>
      _invoke({'task': 'summarize', 'context': _trim(context)});

  static Future<AiResult> smartReplies(List<AiMessage> context) =>
      _invoke({'task': 'smart_replies', 'context': _trim(context)});

  static Future<AiResult> extractActions(List<AiMessage> context) =>
      _invoke({'task': 'extract', 'context': _trim(context)});

  static Future<AiResult> generateReply(
          List<AiMessage> context, String instruction) =>
      _invoke({
        'task': 'reply',
        'context': _trim(context),
        'prompt': instruction,
      });

  /// Free-form assistant chat (the "Allora AI" conversation).
  static Future<AiResult> chat(List<Map<String, String>> history) =>
      _invoke({'task': 'chat', 'history': history});

  static List<Map<String, String>> _trim(List<AiMessage> context) {
    final recent = context.length > _maxContextMessages
        ? context.sublist(context.length - _maxContextMessages)
        : context;
    var total = 0;
    final out = <Map<String, String>>[];
    for (final m in recent.reversed) {
      final t = m.text.length > 800 ? '${m.text.substring(0, 800)}…' : m.text;
      total += t.length;
      if (total > _maxContextChars) break;
      out.insert(0, AiMessage(sender: _scrub(m.sender), text: t).toJson());
    }
    return out;
  }

  /// Strip raw Matrix IDs — the model only needs display names.
  static String _scrub(String sender) {
    if (sender.startsWith('@') && sender.contains(':')) {
      return sender.substring(1, sender.indexOf(':'));
    }
    return sender;
  }

  /// Build assistant context from the most recent timeline messages
  /// (list ordered newest-first, as Timeline.events is).
  static List<AiMessage> contextFromTimeline(
    Room room,
    List<Event> events, {
    int limit = _maxContextMessages,
  }) {
    final result = <AiMessage>[];
    for (final event in events) {
      if (result.length >= limit) break;
      if (event.type != EventTypes.Message) continue;
      if (event.redacted) continue;
      final body = event.content['body']?.toString().trim() ?? '';
      if (body.isEmpty) continue;
      final isMe = event.senderId == room.client.userID;
      final sender =
          isMe ? 'Me' : event.senderFromMemoryOrFallback.calcDisplayname();
      result.add(AiMessage(sender: sender, text: body));
    }
    return result.reversed.toList(); // oldest → newest for the model
  }
}

/// Local store for the "Allora AI" assistant conversation. Fully on-device,
/// cleared with one tap; skipped entirely when AI history is disabled or
/// incognito is on.
class AiChatStore {
  static const _key = 'allora_ai_chat_history_v1';
  static const maxMessages = 200;

  static Future<List<Map<String, String>>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => {
                'role': m['role']?.toString() ?? 'user',
                'text': m['text']?.toString() ?? '',
              })
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Map<String, String>> history) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = history.length > maxMessages
        ? history.sublist(history.length - maxMessages)
        : history;
    await prefs.setString(_key, jsonEncode(trimmed));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

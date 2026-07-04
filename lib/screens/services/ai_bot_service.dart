/// REMOVED in v2.
///
/// The old `AIBotService` daemon listened to *every* timeline event and
/// auto-replied **as the user** in **every room** — including bridged
/// WhatsApp/Telegram chats — with canned rule-based text. That is a serious
/// correctness and privacy bug, not an assistant.
///
/// Allora AI now lives in:
///   * `lib/data/services/ai_service.dart`  — server-backed AI client
///     (Supabase Edge Function; no keys in the app, no fake regex replies)
///   * `lib/features/ai/`                   — assistant UI (compose sheet,
///     smart replies, Allora AI chat)
///
/// This file is intentionally empty and no longer imported anywhere; it is
/// kept only because the deployment sandbox forbids deleting files.
library removed_ai_bot_service;

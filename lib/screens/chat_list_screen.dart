/// MOVED in v2: the chat list now lives in the feature module.
/// This re-export keeps older imports (e.g. the OTP screen) working while
/// guaranteeing there is exactly one implementation.
library;

export '../features/chat_list/chat_list_screen.dart' show ChatListScreen;

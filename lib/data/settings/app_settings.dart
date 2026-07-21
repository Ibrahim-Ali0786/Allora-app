import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A message the user starred/bookmarked. Stored locally.
class StarredMessage {
  final String roomId;
  final String eventId;
  final String roomName;
  final String senderName;
  final String preview;
  final int tsMs;

  const StarredMessage({
    required this.roomId,
    required this.eventId,
    required this.roomName,
    required this.senderName,
    required this.preview,
    required this.tsMs,
  });

  Map<String, dynamic> toJson() => {
        'roomId': roomId, 'eventId': eventId, 'roomName': roomName,
        'senderName': senderName, 'preview': preview, 'tsMs': tsMs,
      };

  factory StarredMessage.fromJson(Map<String, dynamic> j) => StarredMessage(
        roomId: j['roomId'] as String? ?? '',
        eventId: j['eventId'] as String? ?? '',
        roomName: j['roomName'] as String? ?? '',
        senderName: j['senderName'] as String? ?? '',
        preview: j['preview'] as String? ?? '',
        tsMs: j['tsMs'] as int? ?? 0,
      );
}

/// Immutable snapshot of every user preference. Persisted as one JSON blob;
/// all mutation goes through [SettingsController] so persistence can never
/// be forgotten at a call-site.
class AppSettingsState {
  // ── Appearance ──
  final ThemeMode themeMode;
  final int accentIndex;
  final double fontScale;
  final bool amoledBlack;
  final bool reduceMotion;
  final bool highContrast;
  final String bio;
  final String displayName;
  final bool floatingChatEnabled;

  // ── Privacy / Incognito ──
  final bool incognito; // master switch
  final bool hideTyping; // never send typing notifications
  final bool hideReadReceipts; // never send read markers
  final bool blockScreenshots; // Android FLAG_SECURE
  final bool aiHistoryEnabled; // keep local Allora AI conversation

  // ── App lock ──
  final bool appLockEnabled;
  final bool biometricEnabled;
  final String? pinHash;
  final String? pinSalt;
  final int autoLockMinutes; // 0 = lock immediately on background

  // ── Per-chat preferences (local, instant) ──
  final Set<String> pinnedChats;
  final Set<String> archivedChats;
  final Set<String> hiddenChats;
  final Map<String, int> disappearingSeconds; // roomId -> ttl seconds (0=off)

  // ── Bookmarks ──
  final List<StarredMessage> starred;

  // ── AI ──
  final bool aiEnabled;
  final bool aiSmartReplies;
  final String aiTranslateLanguage;

  const AppSettingsState({
    this.themeMode = ThemeMode.system,
    this.accentIndex = 0,
    this.fontScale = 1.0,
    this.amoledBlack = false,
    this.reduceMotion = false,
    this.highContrast = false,
    this.bio = '',
    this.displayName = '',
    this.floatingChatEnabled = false,
    this.incognito = false,
    this.hideTyping = false,
    this.hideReadReceipts = false,
    this.blockScreenshots = false,
    this.aiHistoryEnabled = true,
    this.appLockEnabled = false,
    this.biometricEnabled = false,
    this.pinHash,
    this.pinSalt,
    this.autoLockMinutes = 1,
    this.pinnedChats = const {},
    this.archivedChats = const {},
    this.hiddenChats = const {},
    this.disappearingSeconds = const {},
    this.starred = const [],
    this.aiEnabled = true,
    this.aiSmartReplies = true,
    this.aiTranslateLanguage = 'English',
  });

  /// Effective privacy flags: incognito implies every "hide" flag.
  bool get effectiveHideTyping => incognito || hideTyping;
  bool get effectiveHideReadReceipts => incognito || hideReadReceipts;
  bool get effectiveBlockScreenshots => incognito || blockScreenshots;
  bool get effectiveAiHistory => !incognito && aiHistoryEnabled;

  AppSettingsState copyWith({
    ThemeMode? themeMode,
    int? accentIndex,
    double? fontScale,
    bool? amoledBlack,
    bool? reduceMotion,
    bool? highContrast,
    String? bio,
    String? displayName,
    bool? floatingChatEnabled,
    bool? incognito,
    bool? hideTyping,
    bool? hideReadReceipts,
    bool? blockScreenshots,
    bool? aiHistoryEnabled,
    bool? appLockEnabled,
    bool? biometricEnabled,
    String? pinHash,
    String? pinSalt,
    bool clearPin = false,
    int? autoLockMinutes,
    Set<String>? pinnedChats,
    Set<String>? archivedChats,
    Set<String>? hiddenChats,
    Map<String, int>? disappearingSeconds,
    List<StarredMessage>? starred,
    bool? aiEnabled,
    bool? aiSmartReplies,
    String? aiTranslateLanguage,
  }) {
    return AppSettingsState(
      themeMode: themeMode ?? this.themeMode,
      accentIndex: accentIndex ?? this.accentIndex,
      fontScale: fontScale ?? this.fontScale,
      amoledBlack: amoledBlack ?? this.amoledBlack,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      highContrast: highContrast ?? this.highContrast,
      bio: bio ?? this.bio,
      displayName: displayName ?? this.displayName,
      floatingChatEnabled: floatingChatEnabled ?? this.floatingChatEnabled,
      incognito: incognito ?? this.incognito,
      hideTyping: hideTyping ?? this.hideTyping,
      hideReadReceipts: hideReadReceipts ?? this.hideReadReceipts,
      blockScreenshots: blockScreenshots ?? this.blockScreenshots,
      aiHistoryEnabled: aiHistoryEnabled ?? this.aiHistoryEnabled,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      pinHash: clearPin ? null : (pinHash ?? this.pinHash),
      pinSalt: clearPin ? null : (pinSalt ?? this.pinSalt),
      autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
      pinnedChats: pinnedChats ?? this.pinnedChats,
      archivedChats: archivedChats ?? this.archivedChats,
      hiddenChats: hiddenChats ?? this.hiddenChats,
      disappearingSeconds: disappearingSeconds ?? this.disappearingSeconds,
      starred: starred ?? this.starred,
      aiEnabled: aiEnabled ?? this.aiEnabled,
      aiSmartReplies: aiSmartReplies ?? this.aiSmartReplies,
      aiTranslateLanguage: aiTranslateLanguage ?? this.aiTranslateLanguage,
    );
  }

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.index,
        'accentIndex': accentIndex,
        'fontScale': fontScale,
        'amoledBlack': amoledBlack,
        'reduceMotion': reduceMotion,
        'highContrast': highContrast,
        'bio': bio,
        'displayName': displayName,
        'floatingChatEnabled': floatingChatEnabled,
        'incognito': incognito,
        'hideTyping': hideTyping,
        'hideReadReceipts': hideReadReceipts,
        'blockScreenshots': blockScreenshots,
        'aiHistoryEnabled': aiHistoryEnabled,
        'appLockEnabled': appLockEnabled,
        'biometricEnabled': biometricEnabled,
        'pinHash': pinHash,
        'pinSalt': pinSalt,
        'autoLockMinutes': autoLockMinutes,
        'pinnedChats': pinnedChats.toList(),
        'archivedChats': archivedChats.toList(),
        'hiddenChats': hiddenChats.toList(),
        'disappearingSeconds': disappearingSeconds,
        'starred': starred.map((s) => s.toJson()).toList(),
        'aiEnabled': aiEnabled,
        'aiSmartReplies': aiSmartReplies,
        'aiTranslateLanguage': aiTranslateLanguage,
      };

  factory AppSettingsState.fromJson(Map<String, dynamic> j) {
    Set<String> asSet(dynamic v) =>
        v is List ? v.whereType<String>().toSet() : const <String>{};
    return AppSettingsState(
      themeMode: ThemeMode
          .values[(j['themeMode'] as int? ?? 0).clamp(0, ThemeMode.values.length - 1)],
      accentIndex: j['accentIndex'] as int? ?? 0,
      fontScale: (j['fontScale'] as num?)?.toDouble() ?? 1.0,
      amoledBlack: j['amoledBlack'] as bool? ?? false,
      reduceMotion: j['reduceMotion'] as bool? ?? false,
      highContrast: j['highContrast'] as bool? ?? false,
      bio: j['bio'] as String? ?? '',
      displayName: j['displayName'] as String? ?? '',
      floatingChatEnabled: j['floatingChatEnabled'] as bool? ?? false,
      incognito: j['incognito'] as bool? ?? false,
      hideTyping: j['hideTyping'] as bool? ?? false,
      hideReadReceipts: j['hideReadReceipts'] as bool? ?? false,
      blockScreenshots: j['blockScreenshots'] as bool? ?? false,
      aiHistoryEnabled: j['aiHistoryEnabled'] as bool? ?? true,
      appLockEnabled: j['appLockEnabled'] as bool? ?? false,
      biometricEnabled: j['biometricEnabled'] as bool? ?? false,
      pinHash: j['pinHash'] as String?,
      pinSalt: j['pinSalt'] as String?,
      autoLockMinutes: j['autoLockMinutes'] as int? ?? 1,
      pinnedChats: asSet(j['pinnedChats']),
      archivedChats: asSet(j['archivedChats']),
      hiddenChats: asSet(j['hiddenChats']),
      disappearingSeconds: (j['disappearingSeconds'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
          const {},
      starred: (j['starred'] as List?)
              ?.whereType<Map>()
              .map((m) => StarredMessage.fromJson(Map<String, dynamic>.from(m)))
              .toList() ??
          const [],
      aiEnabled: j['aiEnabled'] as bool? ?? true,
      aiSmartReplies: j['aiSmartReplies'] as bool? ?? true,
      aiTranslateLanguage: j['aiTranslateLanguage'] as String? ?? 'English',
    );
  }
}

class SettingsController extends StateNotifier<AppSettingsState> {
  static const _prefsKey = 'allora_app_settings_v1';
  final SharedPreferences _prefs;

  SettingsController(this._prefs) : super(_hydrate(_prefs));

  static AppSettingsState _hydrate(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return const AppSettingsState();
      return AppSettingsState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettingsState();
    }
  }

  void _commit(AppSettingsState next) {
    state = next;
    _prefs.setString(_prefsKey, jsonEncode(next.toJson()));
  }

  // ── Appearance ──
  void setThemeMode(ThemeMode mode) => _commit(state.copyWith(themeMode: mode));
  void setAccent(int index) => _commit(state.copyWith(accentIndex: index));
  void setFontScale(double scale) => _commit(state.copyWith(fontScale: scale));
  void setAmoledBlack(bool v) => _commit(state.copyWith(amoledBlack: v));
  void setReduceMotion(bool v) => _commit(state.copyWith(reduceMotion: v));
  void setHighContrast(bool v) => _commit(state.copyWith(highContrast: v));
  void setBio(String v) => _commit(state.copyWith(bio: v));
  void setDisplayName(String v) => _commit(state.copyWith(displayName: v));
  void setFloatingChatEnabled(bool v) =>
      _commit(state.copyWith(floatingChatEnabled: v));

  // ── Privacy ──
  void setIncognito(bool v) => _commit(state.copyWith(incognito: v));
  void setHideTyping(bool v) => _commit(state.copyWith(hideTyping: v));
  void setHideReadReceipts(bool v) => _commit(state.copyWith(hideReadReceipts: v));
  void setBlockScreenshots(bool v) => _commit(state.copyWith(blockScreenshots: v));
  void setAiHistoryEnabled(bool v) => _commit(state.copyWith(aiHistoryEnabled: v));

  // ── App lock ──
  void setPin(String pin) {
    final salt = _randomSalt();
    _commit(state.copyWith(
      pinHash: hashPin(pin, salt),
      pinSalt: salt,
      appLockEnabled: true,
    ));
  }

  bool verifyPin(String pin) {
    final salt = state.pinSalt;
    final hash = state.pinHash;
    if (salt == null || hash == null) return false;
    return hashPin(pin, salt) == hash;
  }

  void disableAppLock() => _commit(state.copyWith(
      appLockEnabled: false, biometricEnabled: false, clearPin: true));
  void setBiometric(bool v) => _commit(state.copyWith(biometricEnabled: v));
  void setAutoLockMinutes(int v) => _commit(state.copyWith(autoLockMinutes: v));

  static String hashPin(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt::$pin::allora')).toString();

  static String _randomSalt() {
    final r = Random.secure();
    return base64UrlEncode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  // ── Per-chat prefs ──
  void togglePinned(String roomId) {
    final next = Set<String>.from(state.pinnedChats);
    next.contains(roomId) ? next.remove(roomId) : next.add(roomId);
    _commit(state.copyWith(pinnedChats: next));
  }

  void setArchived(String roomId, bool archived) {
    final next = Set<String>.from(state.archivedChats);
    archived ? next.add(roomId) : next.remove(roomId);
    _commit(state.copyWith(archivedChats: next));
  }

  void setHidden(String roomId, bool hidden) {
    final next = Set<String>.from(state.hiddenChats);
    hidden ? next.add(roomId) : next.remove(roomId);
    _commit(state.copyWith(hiddenChats: next));
  }

  void setDisappearing(String roomId, int seconds) {
    final next = Map<String, int>.from(state.disappearingSeconds);
    if (seconds <= 0) {
      next.remove(roomId);
    } else {
      next[roomId] = seconds;
    }
    _commit(state.copyWith(disappearingSeconds: next));
  }

  /// Remove every stored preference for rooms that no longer exist
  /// (called after account disconnects wipe portal rooms).
  void forgetRooms(Iterable<String> roomIds) {
    final ids = roomIds.toSet();
    if (ids.isEmpty) return;
    _commit(state.copyWith(
      pinnedChats: state.pinnedChats.difference(ids),
      archivedChats: state.archivedChats.difference(ids),
      hiddenChats: state.hiddenChats.difference(ids),
      disappearingSeconds: Map.fromEntries(state.disappearingSeconds.entries
          .where((e) => !ids.contains(e.key))),
      starred:
          state.starred.where((s) => !ids.contains(s.roomId)).toList(),
    ));
  }

  // ── Starred ──
  bool isStarred(String eventId) =>
      state.starred.any((s) => s.eventId == eventId);

  void toggleStarred(StarredMessage message) {
    final list = List<StarredMessage>.from(state.starred);
    final idx = list.indexWhere((s) => s.eventId == message.eventId);
    if (idx >= 0) {
      list.removeAt(idx);
    } else {
      list.insert(0, message);
      if (list.length > 500) list.removeLast();
    }
    _commit(state.copyWith(starred: list));
  }

  // ── AI ──
  void setAiEnabled(bool v) => _commit(state.copyWith(aiEnabled: v));
  void setAiSmartReplies(bool v) => _commit(state.copyWith(aiSmartReplies: v));
  void setAiTranslateLanguage(String v) =>
      _commit(state.copyWith(aiTranslateLanguage: v));
}

/// Overridden in main() with the hydrated SharedPreferences instance.
final sharedPrefsProvider =
    Provider<SharedPreferences>((ref) => throw UnimplementedError());

final settingsProvider =
    StateNotifierProvider<SettingsController, AppSettingsState>(
        (ref) => SettingsController(ref.watch(sharedPrefsProvider)));

/// Convenience: reduce-motion flag for animation gating.
final reduceMotionProvider = Provider<bool>(
    (ref) => ref.watch(settingsProvider.select((s) => s.reduceMotion)));

/// Runtime-only lock flag (true = PIN screen is covering the app).
///
/// Initialized ONCE from persisted settings, so the app starts locked with
/// no unlocked first frame — but deliberately not `watch`ed: enabling the
/// lock in Settings must not instantly lock the user out of the screen
/// they're standing on.
final appLockedProvider = StateProvider<bool>((ref) {
  final s = ref.read(settingsProvider);
  return s.appLockEnabled && s.pinHash != null;
});

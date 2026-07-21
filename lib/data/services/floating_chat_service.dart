import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart bridge to the native Android floating-bubble overlay.
///
/// Every call is wrapped so a missing/failed native side can never crash or
/// block the app — on iOS/desktop, or if the channel isn't wired, these are
/// silent no-ops. The bubble itself is a native overlay (Kotlin
/// `BubbleService`), so it survives the app going to the background; it shows
/// the unread count and brings Allora to the front when tapped.
class FloatingChatService {
  FloatingChatService._();

  static const _channel = MethodChannel('app.allorachat.messenger/bubble');

  static bool _shown = false;

  /// True if the user has granted the "display over other apps" permission.
  static Future<bool> hasPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system overlay-permission screen for this app.
  static Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod('requestPermission');
    } catch (_) {}
  }

  /// Show the bubble with an initial [unread] badge. Returns false if the
  /// permission isn't granted (or the platform has no overlay support).
  static Future<bool> show({int unread = 0}) async {
    try {
      final ok =
          await _channel.invokeMethod<bool>('show', {'unread': unread}) ?? false;
      _shown = ok;
      return ok;
    } catch (e) {
      debugPrint('FloatingChat: show failed: $e');
      return false;
    }
  }

  static Future<void> hide() async {
    _shown = false;
    try {
      await _channel.invokeMethod('hide');
    } catch (_) {}
  }

  static Future<void> updateUnread(int unread) async {
    if (!_shown) return;
    try {
      await _channel.invokeMethod('updateUnread', {'unread': unread});
    } catch (_) {}
  }

  static bool get isShown => _shown;
}

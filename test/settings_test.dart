import 'package:allora/data/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SettingsController> freshController() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return SettingsController(prefs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PIN set + verify round-trips, wrong PIN rejected', () async {
    final c = await freshController();
    c.setPin('482913');
    expect(c.state.appLockEnabled, isTrue);
    expect(c.verifyPin('482913'), isTrue);
    expect(c.verifyPin('000000'), isFalse);
    c.disableAppLock();
    expect(c.state.appLockEnabled, isFalse);
    expect(c.state.pinHash, isNull);
  });

  test('pin hash is salted (same pin, different salt → different hash)', () {
    final h1 = SettingsController.hashPin('123456', 'saltA');
    final h2 = SettingsController.hashPin('123456', 'saltB');
    expect(h1, isNot(h2));
  });

  test('chat prefs toggle and persist to a new instance', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c1 = SettingsController(prefs);
    c1.togglePinned('!room:x');
    c1.setArchived('!arch:x', true);
    c1.setHidden('!hide:x', true);
    c1.setDisappearing('!ttl:x', 86400);

    final c2 = SettingsController(prefs); // re-hydrates from the same prefs
    expect(c2.state.pinnedChats, contains('!room:x'));
    expect(c2.state.archivedChats, contains('!arch:x'));
    expect(c2.state.hiddenChats, contains('!hide:x'));
    expect(c2.state.disappearingSeconds['!ttl:x'], 86400);
  });

  test('forgetRooms clears every per-room preference', () async {
    final c = await freshController();
    c.togglePinned('!a:x');
    c.setArchived('!a:x', true);
    c.setHidden('!a:x', true);
    c.setDisappearing('!a:x', 3600);
    c.toggleStarred(const StarredMessage(
      roomId: '!a:x',
      eventId: r'$e1',
      roomName: 'A',
      senderName: 'S',
      preview: 'p',
      tsMs: 1,
    ));

    c.forgetRooms(['!a:x']);
    expect(c.state.pinnedChats, isEmpty);
    expect(c.state.archivedChats, isEmpty);
    expect(c.state.hiddenChats, isEmpty);
    expect(c.state.disappearingSeconds, isEmpty);
    expect(c.state.starred, isEmpty);
  });

  test('incognito implies every hide flag', () async {
    final c = await freshController();
    expect(c.state.effectiveHideTyping, isFalse);
    c.setIncognito(true);
    expect(c.state.effectiveHideTyping, isTrue);
    expect(c.state.effectiveHideReadReceipts, isTrue);
    expect(c.state.effectiveBlockScreenshots, isTrue);
    expect(c.state.effectiveAiHistory, isFalse);
  });

  test('starred list caps at 500', () async {
    final c = await freshController();
    for (var i = 0; i < 510; i++) {
      c.toggleStarred(StarredMessage(
        roomId: '!r:x',
        eventId: '\$e$i',
        roomName: 'R',
        senderName: 'S',
        preview: 'p$i',
        tsMs: i,
      ));
    }
    expect(c.state.starred.length, 500);
  });
}

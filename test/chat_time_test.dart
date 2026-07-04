import 'package:allora/core/utils/chat_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 2, 15, 30); // Thursday

  group('ChatTime.listStamp', () {
    test('same day shows time', () {
      expect(ChatTime.listStamp(DateTime(2026, 7, 2, 9, 5), now: now), '09:05');
    });
    test('this week shows weekday', () {
      expect(ChatTime.listStamp(DateTime(2026, 6, 30, 9, 0), now: now), 'Tue');
    });
    test('same year shows day + month', () {
      expect(ChatTime.listStamp(DateTime(2026, 1, 14), now: now), '14 Jan');
    });
    test('older shows short year', () {
      expect(ChatTime.listStamp(DateTime(2024, 12, 25), now: now), '25 Dec 24');
    });
  });

  group('ChatTime.dayHeader', () {
    test('today / yesterday', () {
      expect(ChatTime.dayHeader(now, now: now), 'Today');
      expect(
          ChatTime.dayHeader(now.subtract(const Duration(days: 1)), now: now),
          'Yesterday');
    });
    test('same year includes weekday', () {
      expect(ChatTime.dayHeader(DateTime(2026, 6, 29), now: now),
          'Monday, 29 June');
    });
    test('other year includes year', () {
      expect(ChatTime.dayHeader(DateTime(2025, 3, 8), now: now),
          '8 March 2025');
    });
  });

  group('ChatTime.duration', () {
    test('formats voice durations', () {
      expect(ChatTime.duration(const Duration(seconds: 42)), '0:42');
      expect(ChatTime.duration(const Duration(minutes: 12, seconds: 5)),
          '12:05');
    });
  });

  group('ChatTime.relative', () {
    test('buckets', () {
      expect(
          ChatTime.relative(now.subtract(const Duration(seconds: 10)),
              now: now),
          'just now');
      expect(
          ChatTime.relative(now.subtract(const Duration(minutes: 5)),
              now: now),
          '5m ago');
      expect(
          ChatTime.relative(now.subtract(const Duration(hours: 3)), now: now),
          '3h ago');
    });
  });
}

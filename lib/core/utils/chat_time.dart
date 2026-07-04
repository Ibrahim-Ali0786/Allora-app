/// Human-friendly timestamp formatting used across the chat list and
/// chat screen. Kept dependency-free so it is trivially unit-testable.
class ChatTime {
  ChatTime._();

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static String hourMinute(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Compact stamp for chat-list rows: "14:32", "Tue", "24 Jun", "24 Jun 24".
  static String listStamp(DateTime t, {DateTime? now}) {
    now ??= DateTime.now();
    if (sameDay(t, now)) return hourMinute(t);
    final diff = now.difference(t);
    if (diff.inDays < 7 && diff.inDays >= 0) {
      return _weekdays[t.weekday - 1];
    }
    if (t.year == now.year) return '${t.day} ${_months[t.month - 1]}';
    return '${t.day} ${_months[t.month - 1]} ${t.year % 100}';
  }

  /// Section header used between message groups: "Today", "Yesterday",
  /// "Tuesday, 24 June" or "24 June 2025".
  static String dayHeader(DateTime t, {DateTime? now}) {
    now ??= DateTime.now();
    if (sameDay(t, now)) return 'Today';
    if (sameDay(t, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    const fullMonths = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December',
    ];
    const fullDays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
    ];
    if (t.year == now.year) {
      return '${fullDays[t.weekday - 1]}, ${t.day} ${fullMonths[t.month - 1]}';
    }
    return '${t.day} ${fullMonths[t.month - 1]} ${t.year}';
  }

  /// "Last synced 2m ago" style relative stamps.
  static String relative(DateTime t, {DateTime? now}) {
    now ??= DateTime.now();
    final d = now.difference(t);
    if (d.inSeconds < 45) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return listStamp(t, now: now);
  }

  /// Duration label for voice messages: "0:42", "12:05".
  static String duration(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

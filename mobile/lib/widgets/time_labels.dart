// mobile/lib/widgets/time_labels.dart
//
// Date and time formats for the inbox, chat bubbles, notifications and
// profile entries. Hand-rolled because intl isn't a dependency and these
// few formats are all the app needs.

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _weekdaysLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String clockLabel(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

int _daysAgo(DateTime t, DateTime now) =>
    DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;

/// Inbox column: "14:05" today, "Yesterday", "Tue" this week, else "12 Sep".
String conversationTimeLabel(DateTime t, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final days = _daysAgo(t, today);
  if (days <= 0) return clockLabel(t);
  if (days == 1) return 'Yesterday';
  if (days < 7) return _weekdays[t.weekday - 1];
  final dayMonth = '${t.day} ${_months[t.month - 1]}';
  return t.year == today.year ? dayMonth : '$dayMonth ${t.year}';
}

/// Chat day separators: "Today", "Yesterday", "Tuesday", else "12 Sep 2026".
String dayHeaderLabel(DateTime t, {DateTime? now}) {
  final days = _daysAgo(t, now ?? DateTime.now());
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return _weekdaysLong[t.weekday - 1];
  return '${t.day} ${_months[t.month - 1]} ${t.year}';
}

/// Notifications: "Just now", "5m", "3h", "2d", else "12 Sep".
String relativeAgoLabel(DateTime t, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(t);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${t.day} ${_months[t.month - 1]}';
}

/// "2025-03-01" -> "Mar 2025". Null for null or unparseable input.
String? monthYearLabel(Object? isoDate) {
  final d = DateTime.tryParse(isoDate?.toString() ?? '');
  return d == null ? null : '${_months[d.month - 1]} ${d.year}';
}

/// Event times: "Tue 22 Sep 2026, 18:30".
String eventDateLabel(DateTime t) =>
    '${_weekdays[t.weekday - 1]} ${t.day} ${_months[t.month - 1]} ${t.year}, ${clockLabel(t)}';

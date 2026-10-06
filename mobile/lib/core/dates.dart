/// Small date labels in the style of the UI concept, without pulling in intl.
library;

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

String monthName(int month) => _months[month - 1];

String _short(int month) => _months[month - 1].substring(0, 3);

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// "Today, Oct 6, 2026", "Yesterday, Oct 5, 2026" or "Oct 3, 2026".
String dayLabel(DateTime d, {DateTime? now}) {
  final today = dayOf(now ?? DateTime.now());
  final day = dayOf(d);
  final date = '${_short(d.month)} ${d.day}, ${d.year}';
  if (day == today) return 'Today, $date';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday, $date';
  return date;
}

/// "October 5, 2026".
String longDate(DateTime d) => '${monthName(d.month)} ${d.day}, ${d.year}';

/// "18:32".
String clock(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);
DateTime startOfNextMonth(DateTime d) => DateTime(d.year, d.month + 1);

// Shared display formatters. Previously three byte-identical mm:ss helpers
// and three near-identical date helpers lived in separate widgets; the mm:ss
// ones all rendered a 90-minute workout as "90:00".

String formatDuration(int totalSeconds) {
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

const _daysLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _daysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthsLong = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// e.g. "Monday, Jan 5" / "Mon, Jan 5" / "Monday, January 5".
String formatDayMonth(DateTime d, {bool shortDay = false, bool longMonth = false}) {
  final day = (shortDay ? _daysShort : _daysLong)[d.weekday - 1];
  final month = (longMonth ? _monthsLong : _monthsShort)[d.month - 1];
  return '$day, $month ${d.day}';
}

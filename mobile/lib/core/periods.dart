/// Days, weeks and months in the user's calendar (Gregorian or Ethiopian)
/// and week start. Everything that groups money by time (Home, Insights,
/// goals) gets its ranges from here.
library;

import 'dates.dart';
import 'ethiopian_calendar.dart';

enum CalendarKind { gregorian, ethiopian }

enum PeriodKind { day, week, month }

class CalendarPrefs {
  const CalendarPrefs({this.calendar = CalendarKind.gregorian, this.weekStartsMonday = true});

  final CalendarKind calendar;
  final bool weekStartsMonday;

  @override
  bool operator ==(Object other) =>
      other is CalendarPrefs && other.calendar == calendar && other.weekStartsMonday == weekStartsMonday;

  @override
  int get hashCode => Object.hash(calendar, weekStartsMonday);
}

/// A span of local days: [start] inclusive, [end] exclusive (both midnight).
class Period {
  const Period(this.kind, this.start, this.end);

  final PeriodKind kind;
  final DateTime start;
  final DateTime end;

  /// Calendar days in the period (DST-safe).
  int get days =>
      DateTime.utc(end.year, end.month, end.day).difference(DateTime.utc(start.year, start.month, start.day)).inDays;

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);

  @override
  bool operator ==(Object other) => other is Period && other.kind == kind && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);
}

class Periods {
  const Periods(this.prefs);

  final CalendarPrefs prefs;

  bool get _ethiopian => prefs.calendar == CalendarKind.ethiopian;

  /// The period of [kind] that contains [t].
  Period containing(PeriodKind kind, DateTime t) {
    final day = dayOf(t);
    switch (kind) {
      case PeriodKind.day:
        return Period(kind, day, _addDays(day, 1));
      case PeriodKind.week:
        final first = prefs.weekStartsMonday ? DateTime.monday : DateTime.sunday;
        final back = (day.weekday - first) % 7;
        final start = _addDays(day, -back);
        return Period(kind, start, _addDays(start, 7));
      case PeriodKind.month:
        if (_ethiopian) {
          final e = toEthiopian(day);
          return Period(kind, fromEthiopian(e.year, e.month, 1), fromEthiopian(e.year, e.month + 1, 1));
        }
        return Period(kind, DateTime(day.year, day.month), DateTime(day.year, day.month + 1));
    }
  }

  /// The period [steps] before (negative) or after this one.
  Period shift(Period p, int steps) {
    if (steps == 0) return p;
    return switch (p.kind) {
      PeriodKind.day => containing(p.kind, _addDays(p.start, steps)),
      PeriodKind.week => containing(p.kind, _addDays(p.start, 7 * steps)),
      PeriodKind.month => _shiftMonth(p, steps),
    };
  }

  Period _shiftMonth(Period p, int steps) {
    if (_ethiopian) {
      final e = toEthiopian(p.start);
      return containing(PeriodKind.month, fromEthiopian(e.year, e.month + steps, 1));
    }
    return containing(PeriodKind.month, DateTime(p.start.year, p.start.month + steps));
  }

  /// Chart buckets: the days of a week or month; a day has one bucket.
  List<Period> buckets(Period p) {
    if (p.kind == PeriodKind.day) return [p];
    return [for (var d = p.start; d.isBefore(p.end); d = _addDays(d, 1)) Period(PeriodKind.day, d, _addDays(d, 1))];
  }

  /// "Today", "Wed, Oct 8, 2026", "Oct 5 – 11", "October 2026"; Ethiopian
  /// names when that calendar is chosen.
  String label(Period p, {DateTime? now}) {
    final today = containing(PeriodKind.day, now ?? DateTime.now());
    switch (p.kind) {
      case PeriodKind.day:
        if (p == today) return 'Today';
        if (p == shift(today, -1)) return 'Yesterday';
        return _ethiopian ? ethiopianLabel(p.start) : dayLabel(p.start, now: now);
      case PeriodKind.week:
        final last = _addDays(p.end, -1);
        if (p == containing(PeriodKind.week, today.start)) return 'This week';
        if (_ethiopian) return '${ethiopianLabel(p.start, withYear: false)} – ${ethiopianLabel(last, withYear: false)}';
        return p.start.month == last.month
            ? '${_short(p.start)} – ${last.day}'
            : '${_short(p.start)} – ${_short(last)}';
      case PeriodKind.month:
        if (_ethiopian) {
          final e = toEthiopian(p.start);
          return '${ethiopianMonths[e.month - 1]} ${e.year}';
        }
        return '${monthName(p.start.month)} ${p.start.year}';
    }
  }

  /// Short label of a chart bucket: weekday letter for weeks, day number for months.
  String bucketLabel(Period bucket, PeriodKind of) {
    if (of == PeriodKind.week) return const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][bucket.start.weekday - 1];
    return '${_ethiopian ? toEthiopian(bucket.start).day : bucket.start.day}';
  }

  static String _short(DateTime d) => '${monthName(d.month).substring(0, 3)} ${d.day}';

  /// Calendar-day arithmetic that stays at local midnight across DST.
  static DateTime _addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
}

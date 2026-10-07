import 'package:finance_app/core/ethiopian_calendar.dart';
import 'package:finance_app/core/periods.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Ethiopian calendar', () {
    test('new year is Sep 11, or Sep 12 before a Gregorian leap year', () {
      expect(fromEthiopian(2019, 1, 1), DateTime(2026, 9, 11));
      expect(fromEthiopian(2016, 1, 1), DateTime(2023, 9, 12));
      expect(toEthiopian(DateTime(2026, 9, 11)), (year: 2019, month: 1, day: 1));
      expect(toEthiopian(DateTime(2023, 9, 12)), (year: 2016, month: 1, day: 1));
    });

    test('Pagume has 6 days before a Gregorian leap year, otherwise 5', () {
      expect(toEthiopian(DateTime(2023, 9, 11)), (year: 2015, month: 13, day: 6));
      expect(toEthiopian(DateTime(2026, 9, 10)), (year: 2018, month: 13, day: 5));
    });

    test('known dates: Genna and Timket', () {
      expect(toEthiopian(DateTime(2026, 1, 7)), (year: 2018, month: 4, day: 29)); // Tahsas 29
      expect(toEthiopian(DateTime(2026, 1, 19)), (year: 2018, month: 5, day: 11)); // Tir 11
    });

    test('round trip over several years, and month overflow both ways', () {
      for (var d = DateTime(2022, 1, 1); d.isBefore(DateTime(2028, 1, 1)); d = DateTime(d.year, d.month, d.day + 1)) {
        final e = toEthiopian(d);
        expect(fromEthiopian(e.year, e.month, e.day), d);
      }
      expect(fromEthiopian(2018, 14, 1), fromEthiopian(2019, 1, 1));
      expect(fromEthiopian(2019, 0, 1), fromEthiopian(2018, 13, 1));
    });
  });

  group('periods', () {
    const greg = Periods(CalendarPrefs());
    const ethio = Periods(CalendarPrefs(calendar: CalendarKind.ethiopian));
    const sunday = Periods(CalendarPrefs(weekStartsMonday: false));
    final wed = DateTime(2026, 10, 8, 15, 30);

    test('day and week (Monday or Sunday start)', () {
      expect(greg.containing(PeriodKind.day, wed).start, DateTime(2026, 10, 8));
      final week = greg.containing(PeriodKind.week, wed);
      expect((week.start, week.end), (DateTime(2026, 10, 5), DateTime(2026, 10, 12)));
      expect(sunday.containing(PeriodKind.week, wed).start, DateTime(2026, 10, 4));
      expect(greg.label(week, now: DateTime(2026, 11, 20)), 'Oct 5 – 11');
      expect(greg.label(week, now: wed), 'This week');
    });

    test('Gregorian and Ethiopian months, shifting back across the year', () {
      final g = greg.containing(PeriodKind.month, wed);
      expect((g.start, g.end), (DateTime(2026, 10), DateTime(2026, 11)));
      expect(greg.shift(g, -10).start, DateTime(2025, 12));

      final e = ethio.containing(PeriodKind.month, wed); // Meskerem 2019
      expect((e.start, e.end), (DateTime(2026, 9, 11), DateTime(2026, 10, 11)));
      expect(ethio.label(e, now: wed), 'Meskerem 2019');
      final pagume = ethio.shift(e, -1);
      expect((pagume.start, pagume.days), (DateTime(2026, 9, 6), 5));
      expect(ethio.label(pagume, now: wed), 'Pagume 2018');
    });

    test('buckets are the days of the period', () {
      final week = greg.containing(PeriodKind.week, wed);
      expect(greg.buckets(week), hasLength(7));
      expect(greg.bucketLabel(greg.buckets(week).first, PeriodKind.week), 'M');
      expect(ethio.buckets(ethio.containing(PeriodKind.month, wed)), hasLength(30));
    });
  });
}

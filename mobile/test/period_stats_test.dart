import 'package:finance_app/core/periods.dart';
import 'package:finance_app/domain/category.dart';
import 'package:finance_app/domain/transaction.dart';
import 'package:finance_app/features/insights/period_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const periods = Periods(CalendarPrefs());
  const categories = {
    'food': Category(id: 'food', name: 'Food'),
    'coffee': Category(id: 'coffee', name: 'Coffee', parentId: 'food'),
    'transport': Category(id: 'transport', name: 'Transport'),
  };
  var n = 0;
  Txn t(
    DateTime at,
    int birr, {
    TransactionType type = TransactionType.expense,
    int fee = 0,
    String? cat,
    String? who,
  }) => Txn(
    id: 't${n++}',
    accountId: 'a',
    type: type,
    amount: birr * 100,
    fee: fee * 100,
    occurredAt: at,
    categoryId: cat,
    counterpartyName: who,
  );

  final week = periods.containing(PeriodKind.week, DateTime(2026, 10, 8)); // Mon Oct 5 – Sun Oct 11
  final txns = [
    t(DateTime(2026, 10, 5, 9), 100, cat: 'coffee', who: 'Kaldi'),
    t(DateTime(2026, 10, 5, 13), 400, fee: 2, cat: 'food', who: 'KALDI'),
    t(DateTime(2026, 10, 7, 8), 300, cat: 'transport', who: 'Ride'),
    t(DateTime(2026, 10, 7, 18), 5000, type: TransactionType.income, who: 'Salary'),
    t(DateTime(2026, 10, 8, 10), 1000, type: TransactionType.transfer),
    t(DateTime(2026, 10, 4, 23), 999, cat: 'food'), // the Sunday before: outside
  ];

  test('totals: expenses with fees, income, transfers left out, outside dates ignored', () {
    final s = PeriodStats.of(txns, week, periods, categories);
    expect((s.spent, s.income, s.net, s.fees, s.count), (80200, 500000, 419800, 200, 5));
  });

  test('categories roll up to the top level; people merge by name key', () {
    final s = PeriodStats.of(txns, week, periods, categories);
    expect(s.byCategory.first, (categoryId: 'food', amount: 50200));
    expect(s.topCounterparties.first, (name: 'Kaldi', amount: 50200, count: 2));
    expect(s.biggest.first.amount, 40000);
  });

  test('daily buckets for the chart', () {
    final s = PeriodStats.of(txns, week, periods, categories);
    expect(s.buckets, hasLength(7));
    expect(s.buckets[0].spent, 50200);
    expect(s.buckets[2].income, 500000);
    expect(s.buckets[6].spent, 0);
  });

  test('average and projection use the days elapsed so far', () {
    final s = PeriodStats.of(txns, week, periods, categories);
    final thursday = DateTime(2026, 10, 8, 20); // 4 of 7 days
    expect(s.daysElapsed(thursday), 4);
    expect(s.dailyAverage(thursday), 80200 ~/ 4);
    expect(s.projectedSpent(thursday), 80200 * 7 ~/ 4);
    expect(s.projectedSpent(DateTime(2026, 10, 20)), isNull, reason: 'the week is over');
  });

  test('percent change', () {
    expect(percentChange(120, 100), 20);
    expect(percentChange(80, 100), -20);
    expect(percentChange(50, 0), isNull);
  });
}

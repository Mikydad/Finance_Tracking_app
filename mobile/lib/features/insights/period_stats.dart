import '../../core/periods.dart';
import '../../domain/category.dart';
import '../../domain/counterparty.dart';
import '../../domain/transaction.dart';

/// Money that left or arrived in a period, and where it went. Same rules as
/// Home: spending is expenses plus their fees; transfers between your own
/// accounts are neither spending nor income.
class PeriodStats {
  PeriodStats._({
    required this.period,
    required this.spent,
    required this.income,
    required this.fees,
    required this.count,
    required this.byCategory,
    required this.topCounterparties,
    required this.biggest,
    required this.buckets,
  });

  factory PeriodStats.of(List<Txn> txns, Period period, Periods periods, Map<String, Category> categories) {
    var spent = 0, income = 0, fees = 0, count = 0;
    final byCategory = <String?, int>{};
    final byCounterparty = <String, ({String name, int amount, int count})>{};
    final bucketPeriods = periods.buckets(period);
    final bucketSpent = List.filled(bucketPeriods.length, 0);
    final bucketIncome = List.filled(bucketPeriods.length, 0);
    final expenses = <Txn>[];

    for (final t in txns) {
      if (!period.contains(t.occurredAt)) continue;
      count++;
      fees += t.fee;
      final b = bucketPeriods.indexWhere((p) => p.contains(t.occurredAt));
      switch (t.type) {
        case TransactionType.expense:
          final cost = t.amount + t.fee;
          spent += cost;
          expenses.add(t);
          final c = categories[t.categoryId];
          final root = c?.parentId ?? c?.id;
          byCategory[root] = (byCategory[root] ?? 0) + cost;
          final key = nameKey(t.counterpartyName) ?? accountKey(t.counterpartyAccount);
          if (key != null) {
            final prev = byCounterparty[key];
            byCounterparty[key] = (
              name: prev?.name ?? t.counterpartyName ?? t.counterpartyAccount!,
              amount: (prev?.amount ?? 0) + cost,
              count: (prev?.count ?? 0) + 1,
            );
          }
          if (b >= 0) bucketSpent[b] += cost;
        case TransactionType.income:
          income += t.amount;
          if (b >= 0) bucketIncome[b] += t.amount;
        case TransactionType.transfer:
          break;
      }
    }

    final categoryRows = [for (final e in byCategory.entries) (categoryId: e.key, amount: e.value)]
      ..sort((a, b) => b.amount.compareTo(a.amount));
    final people = byCounterparty.values.toList()..sort((a, b) => b.amount.compareTo(a.amount));
    expenses.sort((a, b) => (b.amount + b.fee).compareTo(a.amount + a.fee));

    return PeriodStats._(
      period: period,
      spent: spent,
      income: income,
      fees: fees,
      count: count,
      byCategory: categoryRows,
      topCounterparties: people.take(5).toList(),
      biggest: expenses.take(5).toList(),
      buckets: [
        for (var i = 0; i < bucketPeriods.length; i++)
          (period: bucketPeriods[i], spent: bucketSpent[i], income: bucketIncome[i]),
      ],
    );
  }

  final Period period;
  final int spent;
  final int income;
  final int fees;
  final int count;
  final List<({String? categoryId, int amount})> byCategory;
  final List<({String name, int amount, int count})> topCounterparties;
  final List<Txn> biggest;
  final List<({Period period, int spent, int income})> buckets;

  int get net => income - spent;

  /// Days of the period that have started by [now] (all of a past period).
  int daysElapsed(DateTime now) {
    if (!now.isBefore(period.end)) return period.days;
    if (now.isBefore(period.start)) return 0;
    return Period(PeriodKind.day, period.start, DateTime(now.year, now.month, now.day + 1)).days;
  }

  /// Average spending per elapsed day.
  int dailyAverage(DateTime now) {
    final days = daysElapsed(now);
    return days == 0 ? 0 : spent ~/ days;
  }

  /// Spending at the end of the period if the pace so far holds; null for a
  /// period that's over or hasn't started.
  int? projectedSpent(DateTime now) {
    if (!period.contains(now)) return null;
    final elapsed = daysElapsed(now);
    return elapsed == 0 ? spent : spent * period.days ~/ elapsed;
  }
}

/// Percent change from [previous] to [current]; null when there's nothing to compare.
int? percentChange(int current, int previous) => previous == 0 ? null : ((current - previous) * 100 / previous).round();

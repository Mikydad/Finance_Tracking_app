import '../../core/periods.dart';
import '../../domain/category.dart';
import '../../domain/goal.dart';
import '../../domain/transaction.dart';
import '../goals/goal_progress.dart';
import '../insights/period_stats.dart';

/// What the AI coach reads: this and last week and month, by category and
/// person, the biggest expenses with their reasons, and every goal with its
/// progress. All numbers are computed here (in birr, rounded), so the model
/// only interprets them.
Map<String, Object?> buildCoachSummary({
  required List<Txn> txns,
  required Periods periods,
  required Map<String, Category> categories,
  required List<GoalProgress> goals,
  required DateTime now,
}) {
  double birr(int santim) => (santim / 100).roundToDouble();

  Map<String, Object?> period(PeriodKind kind, {required bool detailed}) {
    final p = periods.containing(kind, now);
    final s = PeriodStats.of(txns, p, periods, categories);
    final prev = PeriodStats.of(txns, periods.shift(p, -1), periods, categories);
    return {
      'label': periods.label(p, now: now),
      'days_total': p.days,
      'days_elapsed': s.daysElapsed(now),
      'spent': birr(s.spent),
      'income': birr(s.income),
      'net': birr(s.net),
      'fees': birr(s.fees),
      'transactions': s.count,
      'daily_average_spent': birr(s.dailyAverage(now)),
      'projected_spent_by_end': s.projectedSpent(now) == null ? null : birr(s.projectedSpent(now)!),
      'spent_by_category': [
        for (final c in s.byCategory.take(detailed ? 10 : 6))
          {
            'category': categories[c.categoryId]?.name ?? 'Uncategorized',
            'spent': birr(c.amount),
            'previous_period': birr(
              prev.byCategory.where((x) => x.categoryId == c.categoryId).firstOrNull?.amount ?? 0,
            ),
          },
      ],
      if (detailed) ...{
        'top_people_and_shops': [
          for (final x in s.topCounterparties) {'name': x.name, 'spent': birr(x.amount), 'payments': x.count},
        ],
        'biggest_expenses': [
          for (final t in s.biggest)
            {
              'to': t.counterpartyName ?? t.counterpartyAccount ?? 'unknown',
              'amount': birr(t.amount + t.fee),
              'category': categories[t.categoryId]?.name ?? 'Uncategorized',
              'reason': ?t.notes,
              'date': t.occurredAt.toIso8601String().substring(0, 10),
            },
        ],
      },
      'previous_period': {
        'label': periods.label(prev.period, now: now),
        'spent': birr(prev.spent),
        'income': birr(prev.income),
      },
    };
  }

  return {
    'today': now.toIso8601String().substring(0, 10),
    'calendar': periods.prefs.calendar.name,
    'this_week': period(PeriodKind.week, detailed: true),
    'this_month': period(PeriodKind.month, detailed: true),
    'goals': [
      for (final g in goals)
        {
          'goal': g.title(categories[g.goal.categoryId]?.name),
          'type': switch (g.goal.kind) {
            GoalKind.spendMax => 'spending limit',
            GoalKind.earnMin => 'earning target',
            GoalKind.saveMin => 'saving target (income minus spending)',
          },
          'target': birr(g.goal.amount),
          'so_far': birr(g.actual),
          'projected_by_end': birr(g.projected),
          'days_left': g.daysLeft,
          'status': g.statusLabel,
          'can_spend_per_day': g.perDayLeft == null ? null : birr(g.perDayLeft!),
        },
    ],
  };
}

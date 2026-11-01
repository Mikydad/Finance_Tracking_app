import '../../core/money.dart';
import '../../core/periods.dart';
import '../../domain/category.dart';
import '../../domain/goal.dart';
import '../../domain/transaction.dart';
import '../insights/category_period_screen.dart';
import '../insights/period_stats.dart';

enum GoalStatus { onTrack, atRisk, missed, reached }

/// Where a goal stands in its current week or month. Plain arithmetic on the
/// phone; the AI coach builds on these numbers.
class GoalProgress {
  GoalProgress._({
    required this.goal,
    required this.period,
    required this.actual,
    required this.projected,
    required this.daysLeft,
    required this.status,
  });

  factory GoalProgress.of(Goal goal, List<Txn> txns, Periods periods, Map<String, Category> categories, DateTime now) {
    final period = periods.containing(goal.period, now);
    final inScope = goal.categoryId == null
        ? txns
        : txns.where((t) => CategoryPeriodScreen.belongs(t, goal.categoryId, categories)).toList();
    final stats = PeriodStats.of(inScope, period, periods, categories);
    final elapsed = stats.daysElapsed(now);
    final daysLeft = period.days - elapsed + 1; // today still counts
    final fraction = elapsed / period.days;

    final actual = switch (goal.kind) {
      GoalKind.spendMax => stats.spent,
      GoalKind.earnMin => stats.income,
      GoalKind.saveMin => stats.net,
    };
    final projected = fraction == 0 ? actual : (actual / fraction).round();

    final status = switch (goal.kind) {
      GoalKind.spendMax when actual > goal.amount => GoalStatus.missed,
      GoalKind.spendMax when projected > goal.amount => GoalStatus.atRisk,
      GoalKind.spendMax => GoalStatus.onTrack,
      _ when actual >= goal.amount => GoalStatus.reached,
      // Income comes in lumps (salary), so judge it against the share of the
      // period that has passed rather than extrapolating.
      _ when actual >= goal.amount * fraction => GoalStatus.onTrack,
      _ => GoalStatus.atRisk,
    };

    return GoalProgress._(
      goal: goal,
      period: period,
      actual: actual,
      projected: projected,
      daysLeft: daysLeft,
      status: status,
    );
  }

  final Goal goal;
  final Period period;

  /// Spent, earned, or saved (income − spending) so far; santim.
  final int actual;

  /// [actual] scaled to the whole period at the pace so far.
  final int projected;
  final int daysLeft;
  final GoalStatus status;

  /// 0..1 (can exceed 1 when over a limit or past a target).
  double get fraction => goal.amount == 0 ? 0 : actual / goal.amount;

  /// For a spending limit: what can still be spent per remaining day.
  int? get perDayLeft {
    if (goal.kind != GoalKind.spendMax || daysLeft <= 0) return null;
    final left = goal.amount - actual;
    return left <= 0 ? 0 : left ~/ daysLeft;
  }

  /// "Spend at most 5,000 ETB this week".
  String title(String? categoryName) {
    final amount = '${formatBirrCompact(goal.amount)} ETB';
    final when = goal.period == PeriodKind.week ? 'a week' : 'a month';
    return switch (goal.kind) {
      GoalKind.spendMax => 'Spend at most $amount${categoryName == null ? '' : ' on $categoryName'} $when',
      GoalKind.earnMin => 'Earn $amount $when',
      GoalKind.saveMin => 'Save $amount $when',
    };
  }

  /// "3,200 of 5,000 · 4 days left · ~450/day".
  String get detail {
    final parts = ['${formatBirrCompact(actual < 0 ? 0 : actual)} of ${formatBirrCompact(goal.amount)}'];
    if (status != GoalStatus.reached) parts.add('$daysLeft ${daysLeft == 1 ? 'day' : 'days'} left');
    final perDay = perDayLeft;
    if (perDay != null && status != GoalStatus.missed) parts.add('~${formatBirrCompact(perDay)}/day');
    return parts.join(' · ');
  }

  String get statusLabel => switch (status) {
    GoalStatus.onTrack => 'On track',
    GoalStatus.atRisk => goal.kind == GoalKind.spendMax ? 'Slow down' : 'Behind',
    GoalStatus.missed => 'Over the limit',
    GoalStatus.reached => 'Reached',
  };
}

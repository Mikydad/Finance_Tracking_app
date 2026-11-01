import 'dart:io';

import 'package:finance_app/core/config.dart';
import 'package:finance_app/core/periods.dart';
import 'package:finance_app/domain/category.dart';
import 'package:finance_app/domain/goal.dart';
import 'package:finance_app/domain/transaction.dart';
import 'package:finance_app/features/coach/coach.dart';
import 'package:finance_app/features/coach/coach_summary.dart';
import 'package:finance_app/features/goals/goal_progress.dart';
import 'package:finance_app/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

import 'categories_screen_test.dart' show FakeCategories;
import 'isar_helper.dart';
import 'manual_tracking_test.dart' show FakeGoals, FakeTransactions;

class FakeCoachApi implements CoachApi {
  Map<String, Object?>? lastSummary;
  bool fail = false;

  @override
  Future<CoachAdvice> ask(Map<String, Object?> summary) async {
    if (fail) throw const SocketException('offline');
    lastSummary = summary;
    return const CoachAdvice(
      headline: 'Food is eating your week',
      assessment: 'You spent 600 of 1,000.',
      suggestions: [(title: 'Cook twice', detail: 'Saves about 300.')],
      goalNotes: [(goal: 'Spend at most 1,000 ETB a week', note: 'About 130/day left.')],
    );
  }
}

void main() {
  const periods = Periods(CalendarPrefs());
  const categories = {'food': Category(id: 'food', name: 'Food')};
  final now = DateTime(2026, 10, 8, 20);
  final txns = [
    Txn(
      id: 'a',
      accountId: 'x',
      type: TransactionType.expense,
      amount: 60000,
      occurredAt: DateTime(2026, 10, 6, 13),
      counterpartyName: 'Kaldi',
      categoryId: 'food',
      notes: 'Team lunch',
    ),
    Txn(id: 'b', accountId: 'x', type: TransactionType.income, amount: 500000, occurredAt: DateTime(2026, 10, 1)),
  ];
  const goal = Goal(id: 'g', kind: GoalKind.spendMax, period: PeriodKind.week, amount: 100000);
  final goals = [GoalProgress.of(goal, txns, periods, categories, now)];

  test('summary: week and month in birr, categories, people, reasons, goals', () {
    final s = buildCoachSummary(txns: txns, periods: periods, categories: categories, goals: goals, now: now);
    final week = s['this_week']! as Map;
    expect((week['spent'], week['income'], week['days_elapsed'], week['days_total']), (600.0, 0.0, 4, 7));
    expect((week['spent_by_category'] as List).single, {'category': 'Food', 'spent': 600.0, 'previous_period': 0.0});
    expect((week['top_people_and_shops'] as List).single, {'name': 'Kaldi', 'spent': 600.0, 'payments': 1});
    expect(((week['biggest_expenses'] as List).single as Map)['reason'], 'Team lunch');
    expect((s['this_month']! as Map)['income'], 5000.0);
    final g = (s['goals']! as List).single as Map;
    expect(
      (g['goal'], g['status'], g['so_far'], g['can_spend_per_day']),
      // 600 in 4 of 7 days is on pace for ~1,050: over the limit.
      ('Spend at most 1,000 ETB a week', 'Slow down', 600.0, 100.0),
    );
  });

  group('controller', () {
    late Isar isar;
    late Directory dir;
    late FakeCoachApi api;

    setUpAll(initIsarForTests);
    setUp(() async {
      (isar, dir) = await openTestIsar();
      api = FakeCoachApi();
    });
    tearDown(() => closeTestIsar(isar, dir));

    ProviderContainer container() => ProviderContainer(
      overrides: [
        configProvider.overrideWithValue(const AppConfig(supabaseUrl: 'u', supabasePublishableKey: 'k')),
        isarProvider.overrideWithValue(isar),
        coachApiProvider.overrideWithValue(api),
        transactionRepositoryProvider.overrideWithValue(FakeTransactions(txns)),
        categoryRepositoryProvider.overrideWithValue(FakeCategories()..rows.addAll(categories.values)),
        goalRepositoryProvider.overrideWithValue(FakeGoals()..goals.add(goal)),
      ],
    );

    test('refresh asks with the summary, shows the advice and keeps it for next time (and offline)', () async {
      final c = container();
      addTearDown(c.dispose);
      c.read(coachProvider);
      await c.read(coachProvider.notifier).refresh();
      expect(c.read(coachProvider).advice!.headline, 'Food is eating your week');
      expect((api.lastSummary!['goals']! as List), hasLength(1));

      // A new session reads the saved advice without the network.
      final next = container();
      addTearDown(next.dispose);
      next.read(coachProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(next.read(coachProvider).advice!.suggestions.single.title, 'Cook twice');
      expect(next.read(coachProvider).updatedAt, isNotNull);
    });

    test('a failed refresh keeps the last advice and says so quietly', () async {
      final c = container();
      addTearDown(c.dispose);
      c.read(coachProvider);
      await c.read(coachProvider.notifier).refresh();
      api.fail = true;
      await c.read(coachProvider.notifier).refresh();
      final s = c.read(coachProvider);
      expect((s.failed, s.loading, s.advice?.headline), (true, false, 'Food is eating your week'));
    });
  });
}

import 'dart:io';

import 'package:finance_app/core/periods.dart';
import 'package:finance_app/data/repositories/goal_repository.dart';
import 'package:finance_app/data/sync/sync_engine.dart';
import 'package:finance_app/domain/category.dart';
import 'package:finance_app/domain/goal.dart';
import 'package:finance_app/domain/transaction.dart';
import 'package:finance_app/features/goals/goal_progress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

import 'isar_helper.dart';
import 'sync_engine_test.dart' show FakeServer;

void main() {
  group('progress', () {
    const periods = Periods(CalendarPrefs());
    const categories = {
      'food': Category(id: 'food', name: 'Food'),
      'coffee': Category(id: 'coffee', name: 'Coffee', parentId: 'food'),
    };
    final thursday = DateTime(2026, 10, 8, 20); // week Mon 5 – Sun 11: day 4 of 7
    var n = 0;
    Txn t(int birr, {TransactionType type = TransactionType.expense, String? cat, int day = 6}) => Txn(
      id: 't${n++}',
      accountId: 'a',
      type: type,
      amount: birr * 100,
      occurredAt: DateTime(2026, 10, day, 12),
      categoryId: cat,
    );
    Goal goal(GoalKind kind, int birr, {String? cat, PeriodKind period = PeriodKind.week}) =>
        Goal(id: 'g', kind: kind, period: period, amount: birr * 100, categoryId: cat);
    GoalProgress of(Goal g, List<Txn> txns) => GoalProgress.of(g, txns, periods, categories, thursday);

    test('spending limit: on track, slow down when the pace would pass it, over when passed', () {
      final limit = goal(GoalKind.spendMax, 5000);
      final ok = of(limit, [t(2000)]);
      expect((ok.status, ok.actual, ok.daysLeft, ok.perDayLeft), (GoalStatus.onTrack, 200000, 4, 75000));
      expect(ok.detail, '2,000 of 5,000 · 4 days left · ~750/day');
      expect(of(limit, [t(3500)]).status, GoalStatus.atRisk, reason: '3,500 in 4 days → ~6,125 a week');
      expect(of(limit, [t(5200)]).status, GoalStatus.missed);
    });

    test('a category limit counts only that category and its children', () {
      final food = of(goal(GoalKind.spendMax, 1000, cat: 'food'), [t(300, cat: 'coffee'), t(4000)]);
      expect(food.actual, 30000);
    });

    test('earning: judged against the share of the period passed; reached when met', () {
      final earn = goal(GoalKind.earnMin, 100000, period: PeriodKind.month);
      // Oct 8 of 31 days: about 26% of the month has passed.
      expect(of(earn, [t(30000, type: TransactionType.income)]).status, GoalStatus.onTrack);
      expect(of(earn, [t(10000, type: TransactionType.income)]).status, GoalStatus.atRisk);
      expect(of(earn, [t(100000, type: TransactionType.income)]).status, GoalStatus.reached);
    });

    test('saving is income minus spending', () {
      final save = of(goal(GoalKind.saveMin, 1000), [t(3000, type: TransactionType.income), t(1500)]);
      expect(save.actual, 150000);
      expect(save.status, GoalStatus.reached);
      expect(save.title(null), 'Save 1,000 ETB a week');
    });

    test('titles', () {
      expect(
        of(goal(GoalKind.spendMax, 3000, cat: 'food'), []).title('Food'),
        'Spend at most 3,000 ETB on Food a week',
      );
      expect(of(goal(GoalKind.earnMin, 100000, period: PeriodKind.month), []).title(null), 'Earn 100,000 ETB a month');
    });
  });

  group('repository and sync', () {
    late Isar isar;
    late Directory dir;
    late GoalRepository repo;
    late FakeServer server;
    final now = DateTime.utc(2026, 10, 8, 12);

    setUpAll(initIsarForTests);
    setUp(() async {
      (isar, dir) = await openTestIsar();
      repo = GoalRepository(isar, clock: () => now, userId: () => 'user-1');
      server = FakeServer();
    });
    tearDown(() => closeTestIsar(isar, dir));

    test('save shows instantly, reaches the server, and a category is dropped for non-spending goals', () async {
      final g = await repo.save(kind: GoalKind.earnMin, period: PeriodKind.month, amount: 10000000, categoryId: 'food');
      expect(g.categoryId, isNull);
      expect((await repo.watchActive().first).single.id, g.id, reason: 'local first');

      await SyncEngine(isar, server, clock: () => now).sync();
      final row = server.rows['finance_goals']![g.id]!;
      expect((row['user_id'], row['kind'], row['period'], row['amount']), ('user-1', 'earn_min', 'month', 10000000));
    });

    test("a goal made on another phone arrives by pull; delete hides it", () async {
      server.put('finance_goals', {
        'id': 'g-remote',
        'kind': 'spend_max',
        'period': 'week',
        'amount': 500000,
        'category_id': null,
        'is_active': true,
        'deleted_at': null,
        'updated_at': '2026-10-08T10:00:00Z',
      });
      final engine = SyncEngine(isar, server, clock: () => now);
      await engine.sync();
      final pulled = (await repo.watchActive().first).single;
      expect((pulled.kind, pulled.period, pulled.amount), (GoalKind.spendMax, PeriodKind.week, 500000));

      await repo.delete('g-remote');
      expect(await repo.watchActive().first, isEmpty);
      await engine.sync();
      expect(server.rows['finance_goals']!['g-remote']!['deleted_at'], isNotNull);
      expect(await repo.watchActive().first, isEmpty, reason: 'the tombstone comes back deleted');
    });

    test('rejects nonsense', () async {
      expect(() => repo.save(kind: GoalKind.spendMax, period: PeriodKind.week, amount: 0), throwsArgumentError);
      expect(() => repo.save(kind: GoalKind.spendMax, period: PeriodKind.day, amount: 100), throwsArgumentError);
    });
  });
}

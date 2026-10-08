import 'dart:async';

import 'package:finance_app/core/config.dart';
import 'package:finance_app/core/theme.dart';
import 'package:finance_app/data/repositories/account_repository.dart';
import 'package:finance_app/data/repositories/transaction_repository.dart';
import 'package:finance_app/domain/account.dart';
import 'package:finance_app/domain/category.dart';
import 'package:finance_app/domain/transaction.dart';
import 'package:finance_app/core/periods.dart';
import 'package:finance_app/data/repositories/goal_repository.dart';
import 'package:finance_app/domain/goal.dart';
import 'package:finance_app/features/goals/goals_screen.dart';
import 'package:finance_app/features/home/home_screen.dart';
import 'package:finance_app/features/insights/category_period_screen.dart';
import 'package:finance_app/features/insights/insights_screen.dart';
import 'package:finance_app/features/transactions/add_transaction_screen.dart';
import 'package:finance_app/features/transactions/transaction_detail_screen.dart';
import 'package:finance_app/features/transactions/transactions_screen.dart';
import 'package:finance_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'categories_screen_test.dart' show FakeCategories;

class FakeTransactions extends TransactionRepository {
  FakeTransactions([List<Txn> initial = const []]) : rows = [...initial];

  final List<Txn> rows;
  final _changes = StreamController<void>.broadcast();
  final deleted = <String>{};

  List<Txn> get _live =>
      rows.where((t) => !deleted.contains(t.id)).toList()..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  @override
  Stream<List<Txn>> watch({TransactionType? type, DateTime? from, DateTime? to, int? limit}) => _watch(
    () => _live
        .where((t) => type == null || t.type == type)
        .where((t) => from == null || !t.occurredAt.isBefore(from))
        .where((t) => to == null || t.occurredAt.isBefore(to))
        .take(limit ?? 1 << 30)
        .toList(),
  );

  @override
  Stream<Txn?> watchOne(String id) => _watch(() => _live.where((t) => t.id == id).firstOrNull);

  @override
  Future<Txn> add({
    required String accountId,
    required TransactionType type,
    required int amount,
    DateTime? occurredAt,
    String? counterpartyName,
    String? categoryId,
    String? notes,
  }) async {
    final t = Txn(
      id: 'new-${rows.length}',
      accountId: accountId,
      type: type,
      amount: amount,
      occurredAt: occurredAt ?? DateTime.now(),
      counterpartyName: counterpartyName,
      categoryId: categoryId,
      notes: notes,
    );
    rows.add(t);
    _changes.add(null);
    return t;
  }

  @override
  Future<void> update(Txn edited) async {
    rows[rows.indexWhere((t) => t.id == edited.id)] = edited;
    _changes.add(null);
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    _changes.add(null);
  }

  @override
  Future<void> restore(String id) async {
    deleted.remove(id);
    _changes.add(null);
  }

  @override
  Future<void> updateNotes(String id, String? notes) async {
    final i = rows.indexWhere((t) => t.id == id);
    rows[i] = rows[i].copyWith(notes: () => notes);
    _changes.add(null);
  }

  @override
  Stream<List<Txn>> watchRelated(Txn txn) => _watch(
    () => _live
        .where((t) => t.id != txn.id && t.counterpartyName != null && t.counterpartyName == txn.counterpartyName)
        .toList(),
  );

  @override
  Future<String?> learnedCategory({String? name, String? account}) async => null;

  @override
  Future<int> applyLearnedCategories() async => 0;

  @override
  Future<List<({Txn txn, String institution})>> receiptCandidates({required DateTime since, int limit = 10}) async =>
      const [];

  @override
  Future<void> applyReceipt(String id, {String? reason, String? counterpartyName, String? counterpartyAccount}) async {}

  @override
  Future<void> receiptFailed(String id, {int maxAttempts = 3}) async {}
}

class FakeGoals implements GoalRepository {
  final goals = <Goal>[];
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<List<Goal>> watchActive() async* {
    yield [...goals];
    await for (final _ in _changes.stream) {
      yield [...goals];
    }
  }

  @override
  Future<Goal> save({
    String? id,
    required GoalKind kind,
    required PeriodKind period,
    required int amount,
    String? categoryId,
  }) async {
    final g = Goal(
      id: id ?? 'goal-${goals.length}',
      kind: kind,
      period: period,
      amount: amount,
      categoryId: categoryId,
    );
    goals
      ..removeWhere((x) => x.id == g.id)
      ..add(g);
    _changes.add(null);
    return g;
  }

  @override
  Future<void> delete(String id) async {
    goals.removeWhere((g) => g.id == id);
    _changes.add(null);
  }
}

class FakeAccounts implements AccountRepository {
  static const cashAccount = Account(id: 'acct-cash', name: 'Cash', institution: 'cash');

  @override
  Future<Account?> cash() async => cashAccount;

  @override
  Future<Account> ensureLocalCash() async => cashAccount;

  @override
  Stream<List<Account>> watchAll() => Stream.value(const [cashAccount]);
}

const categories = [
  Category(id: 'cat-food', key: 'food', name: 'Food'),
  Category(id: 'cat-coffee', key: 'food.coffee', name: 'Coffee', parentId: 'cat-food'),
  Category(id: 'cat-transport', key: 'transport', name: 'Transport'),
  Category(id: 'cat-income', key: 'income', name: 'Income', kind: CategoryKind.income),
];

Txn txn(String id, DateTime at, int amount, {TransactionType type = TransactionType.expense, String? cat}) => Txn(
  id: id,
  accountId: 'acct-cash',
  type: type,
  amount: amount,
  occurredAt: at,
  categoryId: cat,
  counterpartyName: id,
);

Future<FakeTransactions> pumpApp(
  WidgetTester tester,
  String location, {
  List<Txn> txns = const [],
  FakeGoals? goals,
}) async {
  final repo = FakeTransactions(txns);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: '/start',
        builder: (context, _) => TextButton(onPressed: () => context.push('/add'), child: const Text('open')),
      ),
      GoRoute(path: '/add', builder: (_, _) => const AddTransactionScreen()),
      GoRoute(path: '/transactions', builder: (_, _) => const TransactionsScreen()),
      GoRoute(path: '/insights', builder: (_, _) => const InsightsScreen()),
      GoRoute(path: '/goals', builder: (_, _) => const GoalsScreen()),
      GoRoute(
        path: '/insights/category/:id',
        builder: (_, s) => CategoryPeriodScreen(categoryId: s.pathParameters['id'], period: s.extra! as Period),
      ),
      GoRoute(
        path: '/transactions/:id',
        builder: (_, s) => TransactionDetailScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(path: '/transactions/:id/edit', builder: (_, s) => Text('editing ${s.pathParameters['id']}')),
      GoRoute(path: '/transactions/:id/related', builder: (_, s) => Text('related ${s.pathParameters['id']}')),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        configProvider.overrideWithValue(const AppConfig(supabaseUrl: '', supabasePublishableKey: '')),
        transactionRepositoryProvider.overrideWithValue(repo),
        accountRepositoryProvider.overrideWithValue(FakeAccounts()),
        categoryRepositoryProvider.overrideWithValue(FakeCategories()),
        calendarPrefsProvider.overrideWith((_) => Stream.value(const CalendarPrefs())),
        goalRepositoryProvider.overrideWithValue(goals ?? FakeGoals()),
        categoriesProvider.overrideWith((_) => Stream.value(categories)),
        categoryByIdProvider.overrideWith((_) => Stream.value({for (final c in categories) c.id: c})),
      ],
      child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

/// A finger-like swipe: many small moves, as on a phone. (A single jump, as
/// tester.drag sends, skips the point where the full-swipe delete arms.)
Future<void> swipe(WidgetTester tester, Finder finder, double dx) async {
  final gesture = await tester.startGesture(tester.getCenter(finder));
  for (var i = 0; i < 20; i++) {
    await gesture.moveBy(Offset(dx / 20, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('add: amount, name and category are saved to the Cash account', (tester) async {
    final repo = await pumpApp(tester, '/start');
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('amount')), '1,250.50');
    await tester.enterText(find.byKey(const Key('what')), 'Lunch');
    await tester.tap(find.byKey(const Key('category-food')));
    await tester.pump();
    expect(find.byKey(const Key('category-food.coffee')), findsNothing, reason: 'only top-level categories');
    await tester.scrollUntilVisible(find.byKey(const Key('save')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();

    final t = repo.rows.single;
    expect(
      (t.amount, t.counterpartyName, t.categoryId, t.accountId, t.type),
      (125050, 'Lunch', 'cat-food', 'acct-cash', TransactionType.expense),
    );
    expect(find.text('open'), findsOneWidget, reason: 'the screen closes after saving');
  });

  testWidgets('add: "+ New" creates a category without leaving the form and selects it', (tester) async {
    final repo = await pumpApp(tester, '/start');
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '900');
    await tester.scrollUntilVisible(
      find.byKey(const Key('new-category')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('new-category')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('category-name')), 'Business');
    await tester.tap(find.byKey(const Key('save-category')));
    await tester.pumpAndSettle();

    expect(find.text('Add transaction'), findsWidgets, reason: 'still on the form');
    await tester.scrollUntilVisible(find.byKey(const Key('save')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();
    expect(repo.rows.single.categoryId, 'new');
  });

  testWidgets('add: a missing amount shows an error and saves nothing', (tester) async {
    final repo = await pumpApp(tester, '/add');
    await tester.scrollUntilVisible(find.byKey(const Key('save')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter an amount'), findsOneWidget);
    expect(repo.rows, isEmpty);
  });

  testWidgets('add: income shows income categories, not expense ones', (tester) async {
    await pumpApp(tester, '/add');
    await tester.tap(find.text('Income'));
    await tester.pump();
    expect(find.byKey(const Key('category-income')), findsOneWidget);
    expect(find.byKey(const Key('category-transport')), findsNothing);
  });

  testWidgets('add: closing an untouched form leaves at once; a started one asks first', (tester) async {
    await pumpApp(tester, '/start');
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('close')));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '300');
    await tester.pump();
    await tester.tap(find.byKey(const Key('close')));
    await tester.pumpAndSettle();
    expect(find.text('Discard this transaction?'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('amount')), findsOneWidget);

    await tester.tap(find.byKey(const Key('close')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('add: the amount field ignores letters', (tester) async {
    await pumpApp(tester, '/add');
    await tester.enterText(find.byKey(const Key('amount')), 'a1b2,5x0.5');
    expect(tester.widget<TextField>(find.byKey(const Key('amount'))).controller!.text, '12,50.5');
  });

  testWidgets('the "Transaction deleted" message goes away on its own', (tester) async {
    await pumpApp(tester, '/transactions', txns: [txn('Lunch', DateTime.now(), 50000)]);
    await swipe(tester, find.text('Lunch'), -600);
    expect(find.text('Transaction deleted'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Transaction deleted'), findsNothing);
  });

  testWidgets('swipe left shows Edit and Delete; Edit opens the form, Delete deletes', (tester) async {
    final repo = await pumpApp(tester, '/transactions', txns: [txn('Lunch', DateTime.now(), 50000)]);
    await tester.drag(find.text('Lunch'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(repo.deleted, isEmpty, reason: 'a short swipe only reveals the buttons');
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('editing Lunch'), findsOneWidget);

    final router = GoRouter.of(tester.element(find.text('editing Lunch')));
    router.pop();
    await tester.pumpAndSettle();
    await tester.drag(find.text('Lunch'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(repo.deleted, {'Lunch'});
    expect(find.text('Transaction deleted'), findsOneWidget);
  });

  testWidgets('home: recent transactions swipe too', (tester) async {
    await pumpApp(tester, '/', txns: [txn('Lunch', DateTime.now(), 50000)]);
    await tester.drag(find.text('Lunch'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('detail: tap the reason once, type, and it saves when the keyboard closes', (tester) async {
    final repo = await pumpApp(tester, '/transactions/Lunch', txns: [txn('Lunch', DateTime.now(), 50000)]);
    expect(find.text('What was it for? Tap to add'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reason')));
    await tester.enterText(find.byKey(const Key('reason')), 'Team lunch');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(repo.rows.single.notes, 'Team lunch');
  });

  testWidgets('detail: suggests the last reason used with the same person, and links the history', (tester) async {
    final now = DateTime.now();
    final earlier = Txn(
      id: 'earlier',
      accountId: 'acct-cash',
      type: TransactionType.expense,
      amount: 1000000,
      occurredAt: now.subtract(const Duration(days: 30)),
      counterpartyName: 'Dawit',
      notes: 'Rent',
    );
    final current = Txn(
      id: 'current',
      accountId: 'acct-cash',
      type: TransactionType.expense,
      amount: 1000000,
      occurredAt: now,
      counterpartyName: 'Dawit',
    );
    final repo = await pumpApp(tester, '/transactions/current', txns: [earlier, current]);

    expect(find.text('Last time: Rent'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reason-suggestion')));
    await tester.pumpAndSettle();
    expect(repo.rows.firstWhere((t) => t.id == 'current').notes, 'Rent');

    expect(find.text('2 times with Dawit'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('history')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('history')));
    await tester.pumpAndSettle();
    expect(find.text('related current'), findsOneWidget);
  });

  testWidgets('insights: week totals, switch to month, step back to an empty period', (tester) async {
    final now = DateTime.now();
    await pumpApp(
      tester,
      '/insights',
      txns: [
        txn('Lunch', now, 50000, cat: 'cat-coffee'),
        txn('Salary', now, 4200000, type: TransactionType.income, cat: 'cat-income'),
      ],
    );
    expect(find.text('This week'), findsOneWidget);
    expect(find.textContaining('500 ETB', findRichText: true), findsWidgets, reason: 'spent this week');
    expect(find.text('Food'), findsOneWidget, reason: 'coffee rolls up to Food');

    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('insights-spent')), findsOneWidget);

    await tester.tap(find.byKey(const Key('period-back')));
    await tester.pumpAndSettle();
    expect(find.text('No transactions in this period.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('period-forward')));
    await tester.pumpAndSettle();
    expect(find.text('No transactions in this period.'), findsNothing);
  });

  testWidgets('insights: tapping a category lists its transactions for the period', (tester) async {
    final now = DateTime.now();
    await pumpApp(
      tester,
      '/insights',
      txns: [
        txn('Lunch', now, 50000, cat: 'cat-coffee'),
        txn('Bus', now, 3000),
      ],
    );
    await tester.ensureVisible(find.text('Food'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();
    expect(find.text('500 ETB · 1 transaction'), findsOneWidget);
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('Bus'), findsNothing);
  });

  testWidgets('goals: from Home, set a weekly spending limit and see its progress', (tester) async {
    final goals = FakeGoals();
    await pumpApp(tester, '/', txns: [txn('Lunch', DateTime.now(), 50000)], goals: goals);
    await tester.tap(find.byKey(const Key('home-set-goal')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-goal')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('goal-amount')), '5000');
    await tester.tap(find.byKey(const Key('save-goal')));
    await tester.pumpAndSettle();

    expect(goals.goals.single.amount, 500000);
    expect(find.text('Spend at most 5,000 ETB a week'), findsOneWidget);
    expect(find.textContaining('500 of 5,000'), findsOneWidget);
  });

  testWidgets('insights: share a category opens the export sheet set to that category, PDF', (tester) async {
    final now = DateTime.now();
    await pumpApp(tester, '/insights', txns: [txn('Lunch', now, 50000, cat: 'cat-coffee')]);
    await tester.ensureVisible(find.text('Food'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share-category')));
    await tester.pumpAndSettle();

    expect(find.text('Only Food'), findsOneWidget);
    expect(find.text('Show the total of these items'), findsOneWidget, reason: 'PDF is preselected');
    final toggle = tester.widget<SwitchListTile>(find.byKey(const Key('export-total')));
    expect(toggle.value, isFalse, reason: 'totals stay private unless asked');
  });

  testWidgets('transactions: grouped by day, filtered by type, full swipe deletes with undo', (tester) async {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final repo = await pumpApp(
      tester,
      '/transactions',
      txns: [
        txn('Lunch', today, 50000, cat: 'cat-coffee'),
        txn('Salary', yesterday, 4200000, type: TransactionType.income, cat: 'cat-income'),
      ],
    );

    expect(find.textContaining('Today, '), findsOneWidget);
    expect(find.textContaining('Yesterday, '), findsOneWidget);
    expect(find.text('-500 ETB'), findsOneWidget);
    expect(find.text('+42,000 ETB'), findsOneWidget);

    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();
    expect(find.text('Lunch'), findsNothing);
    expect(find.text('Salary'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await swipe(tester, find.text('Lunch'), -600);
    expect(repo.deleted, {'Lunch'});
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(repo.deleted, isEmpty);
    expect(find.text('Lunch'), findsOneWidget);
  });

  testWidgets('detail: shows the automatic badge and the bank reference', (tester) async {
    await pumpApp(
      tester,
      '/transactions/t1',
      txns: [
        Txn(
          id: 't1',
          accountId: 'acct-cash',
          type: TransactionType.expense,
          amount: 250000,
          fee: 1000,
          occurredAt: DateTime(2026, 10, 5, 18, 32),
          counterpartyName: 'ABC Store',
          referenceId: 'FT26278XYZ',
          isAutomatic: true,
        ),
      ],
    );
    expect(find.text('-2,510 ETB'), findsOneWidget);
    expect(find.text('Automatically detected'), findsOneWidget);
    expect(find.text('FT26278XYZ'), findsOneWidget);
    expect(find.text('October 5, 2026'), findsOneWidget);
    expect(find.text('18:32'), findsOneWidget);
  });

  test('month summary: expenses with fees, income left out, children rolled up, change vs last month', () {
    final now = DateTime(2026, 10, 20);
    final byId = {for (final c in categories) c.id: c};
    final s = MonthSummary.of(
      [
        txn('a', DateTime(2026, 10, 2), 10000, cat: 'cat-coffee').withFee(500),
        txn('b', DateTime(2026, 10, 3), 20000, cat: 'cat-food'),
        txn('c', DateTime(2026, 10, 4), 9999900, type: TransactionType.income),
        txn('d', DateTime(2026, 10, 5), 4500),
        txn('e', DateTime(2026, 9, 15), 30000, cat: 'cat-food'),
      ],
      now,
      byId,
    );

    expect(s.spent, 35000);
    expect(s.byCategory.first, (categoryId: 'cat-food', amount: 30500));
    expect(s.byCategory.last, (categoryId: null, amount: 4500));
    expect(s.changePercent, 17);
  });
}

extension on Txn {
  Txn withFee(int fee) => Txn(
    id: id,
    accountId: accountId,
    type: type,
    amount: amount,
    fee: fee,
    occurredAt: occurredAt,
    categoryId: categoryId,
    counterpartyName: counterpartyName,
  );
}

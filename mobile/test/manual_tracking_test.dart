import 'dart:async';

import 'package:finance_app/core/config.dart';
import 'package:finance_app/core/theme.dart';
import 'package:finance_app/data/repositories/account_repository.dart';
import 'package:finance_app/data/repositories/transaction_repository.dart';
import 'package:finance_app/domain/account.dart';
import 'package:finance_app/domain/category.dart';
import 'package:finance_app/domain/transaction.dart';
import 'package:finance_app/features/home/home_screen.dart';
import 'package:finance_app/features/transactions/add_transaction_screen.dart';
import 'package:finance_app/features/transactions/transaction_detail_screen.dart';
import 'package:finance_app/features/transactions/transactions_screen.dart';
import 'package:finance_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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

Future<FakeTransactions> pumpApp(WidgetTester tester, String location, {List<Txn> txns = const []}) async {
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
      GoRoute(
        path: '/transactions/:id',
        builder: (_, s) => TransactionDetailScreen(id: s.pathParameters['id']!),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        configProvider.overrideWithValue(const AppConfig(supabaseUrl: '', supabasePublishableKey: '')),
        transactionRepositoryProvider.overrideWithValue(repo),
        accountRepositoryProvider.overrideWithValue(FakeAccounts()),
        categoriesProvider.overrideWith((_) => Stream.value(categories)),
        categoryByIdProvider.overrideWith((_) => Stream.value({for (final c in categories) c.id: c})),
      ],
      child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
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

  testWidgets('transactions: grouped by day, filtered by type, swipe deletes with undo', (tester) async {
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
    await tester.drag(find.text('Lunch'), const Offset(-500, 0));
    await tester.pumpAndSettle();
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

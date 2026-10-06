import 'dart:convert';
import 'dart:io';

import 'package:finance_app/data/local/models.dart';
import 'package:finance_app/data/repositories/transaction_repository.dart';
import 'package:finance_app/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

import 'isar_helper.dart';

void main() {
  late Isar isar;
  late Directory dir;
  late IsarTransactionRepository repo;
  final now = DateTime.utc(2026, 10, 5, 12);

  setUpAll(initIsarForTests);

  setUp(() async {
    (isar, dir) = await openTestIsar();
    repo = IsarTransactionRepository(isar, clock: () => now);
  });

  tearDown(() => closeTestIsar(isar, dir));

  test('add saves locally and queues one outbox upsert in server column names', () async {
    final txn = await repo.add(
      accountId: 'acct-1',
      type: TransactionType.expense,
      amount: 50000,
      counterpartyName: 'Meron Cafe',
      categoryId: 'cat-coffee',
    );

    expect(await isar.localTransactions.count(), 1);
    final ops = await isar.outboxOps.where().findAll();
    expect(ops, hasLength(1));
    expect(ops.single.table, 'transactions');
    expect(ops.single.op, 'upsert');

    final payload = jsonDecode(ops.single.payload) as Map<String, dynamic>;
    expect(payload['id'], txn.id);
    expect(payload['account_id'], 'acct-1');
    expect(payload['amount'], 50000);
    expect(payload['category_source'], 'user');
    expect(payload['occurred_at'], '2026-10-05T12:00:00.000Z');
  });

  test('watchRecent emits newest first and hides deleted rows', () async {
    final older = await repo.add(
      accountId: 'a',
      type: TransactionType.expense,
      amount: 100,
      occurredAt: now.subtract(const Duration(days: 1)),
    );
    final newer = await repo.add(accountId: 'a', type: TransactionType.income, amount: 200);

    expect((await repo.watchRecent().first).map((t) => t.id), [newer.id, older.id]);

    await repo.delete(older.id);
    expect((await repo.watchRecent().first).map((t) => t.id), [newer.id]);

    final ops = await isar.outboxOps.where().findAll();
    expect(ops.map((o) => o.op), ['upsert', 'upsert', 'delete']);
  });

  test('rejects non-positive amounts', () {
    expect(() => repo.add(accountId: 'a', type: TransactionType.expense, amount: 0), throwsArgumentError);
  });

  test('update writes only the changed columns and marks a picked category as the user\'s', () async {
    final t = await repo.add(accountId: 'a', type: TransactionType.expense, amount: 1000, counterpartyName: 'Shop');
    await isar.writeTxn(() => isar.outboxOps.clear());

    await repo.update(t.copyWith(amount: 1500, categoryId: () => 'cat-food', notes: () => 'with Hana'));

    final op = (await isar.outboxOps.where().findAll()).single;
    final payload = jsonDecode(op.payload) as Map<String, dynamic>;
    expect(payload, {
      'id': t.id,
      'amount': 1500,
      'notes': 'with Hana',
      'category_id': 'cat-food',
      'category_source': 'user',
    });
    final row = await isar.localTransactions.getByUuid(t.id);
    expect((row!.amount, row.categorySource, row.notes), (1500, 'user', 'with Hana'));
  });

  test('editing a transaction that needs review confirms it', () async {
    final t = await repo.add(accountId: 'a', type: TransactionType.expense, amount: 1000);
    await isar.writeTxn(() async {
      final row = (await isar.localTransactions.getByUuid(t.id))!
        ..status = 'needs_review'
        ..reviewReason = 'low_category_confidence';
      await isar.localTransactions.put(row);
      await isar.outboxOps.clear();
    });

    await repo.update(t.copyWith(categoryId: () => 'cat-family'));
    final payload = jsonDecode((await isar.outboxOps.where().findAll()).single.payload) as Map<String, dynamic>;
    expect(payload['status'], 'confirmed');
    expect(payload.containsKey('review_reason'), isTrue);
    expect(payload['review_reason'], isNull);
  });

  test('an update with no changes queues nothing', () async {
    final t = await repo.add(accountId: 'a', type: TransactionType.expense, amount: 1000);
    await isar.writeTxn(() => isar.outboxOps.clear());
    await repo.update(t);
    expect(await isar.outboxOps.count(), 0);
  });

  test('restore undoes a delete and queues deleted_at = null', () async {
    final t = await repo.add(accountId: 'a', type: TransactionType.expense, amount: 1000);
    await repo.delete(t.id);
    expect(await repo.watchOne(t.id).first, isNull);

    await repo.restore(t.id);
    expect((await repo.watchOne(t.id).first)?.id, t.id);
    final last = (await isar.outboxOps.where().findAll()).last;
    expect(jsonDecode(last.payload), {'id': t.id, 'deleted_at': null});
  });

  test('watch filters by type and date range', () async {
    await repo.add(accountId: 'a', type: TransactionType.expense, amount: 1, occurredAt: DateTime(2026, 9, 30));
    final oct = await repo.add(
      accountId: 'a',
      type: TransactionType.expense,
      amount: 2,
      occurredAt: DateTime(2026, 10, 1),
    );
    await repo.add(accountId: 'a', type: TransactionType.income, amount: 3, occurredAt: DateTime(2026, 10, 2));

    final octExpenses = await repo
        .watch(type: TransactionType.expense, from: DateTime(2026, 10), to: DateTime(2026, 11))
        .first;
    expect(octExpenses.map((t) => t.id), [oct.id]);
    expect((await repo.watch(type: TransactionType.income).first).single.amount, 3);
  });

  test('transactions from an SMS or Shortcut source are marked automatic', () async {
    await isar.writeTxn(() async {
      await isar.localSources.putAll([
        LocalSource()
          ..uuid = 'src-shortcut'
          ..type = 'shortcut',
        LocalSource()
          ..uuid = 'src-manual'
          ..type = 'manual',
      ]);
      await isar.localTransactions.putAll([
        for (final (id, src) in [('t-auto', 'src-shortcut'), ('t-manual', 'src-manual'), ('t-none', null)])
          LocalTransaction()
            ..uuid = id
            ..accountId = 'a'
            ..type = 'expense'
            ..amount = 100
            ..occurredAt = now
            ..sourceId = src
            ..updatedAt = now,
      ]);
    });
    final byId = {for (final t in await repo.watch().first) t.id: t.isAutomatic};
    expect(byId, {'t-auto': true, 't-manual': false, 't-none': false});
  });
}

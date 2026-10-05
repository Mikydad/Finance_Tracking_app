import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:finance_app/data/local/isar_db.dart';
import 'package:finance_app/data/local/models.dart';
import 'package:finance_app/data/repositories/transaction_repository.dart';
import 'package:finance_app/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

void main() {
  late Isar isar;
  late Directory dir;
  late IsarTransactionRepository repo;
  final now = DateTime.utc(2026, 10, 5, 12);

  setUpAll(() async {
    // Set ISAR_CORE_LIB to a local libisar for the host (e.g. from the
    // isar_community_flutter_libs package) when the download host is blocked.
    final local = Platform.environment['ISAR_CORE_LIB'];
    await Isar.initializeIsarCore(
      download: local == null,
      libraries: local == null ? const {} : {Abi.current(): local},
    );
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('isar_test');
    isar = await Isar.open(localSchemas, directory: dir.path, name: 'test');
    repo = IsarTransactionRepository(isar, clock: () => now);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    await dir.delete(recursive: true);
  });

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
}

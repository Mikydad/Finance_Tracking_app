import 'dart:async';
import 'dart:io';

import 'package:finance_app/data/local/models.dart';
import 'package:finance_app/data/repositories/account_repository.dart';
import 'package:finance_app/data/repositories/category_repository.dart';
import 'package:finance_app/data/repositories/transaction_repository.dart';
import 'package:finance_app/data/sync/sync_api.dart';
import 'package:finance_app/data/sync/sync_engine.dart';
import 'package:finance_app/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

import 'isar_helper.dart';

/// In-memory stand-in for sync_push / sync_pull with the same contract:
/// one global version sequence, partial upserts, soft deletes, tombstones.
class FakeServer implements SyncApi {
  final rows = <String, Map<String, Map<String, dynamic>>>{};
  final pushed = <List<Map<String, Object?>>>[];
  final rejectIds = <String>{};
  bool offline = false;
  int _version = 0;

  void put(String table, Map<String, dynamic> row) {
    final current = rows.putIfAbsent(table, () => {})[row['id']] ?? {};
    rows[table]![row['id'] as String] = {...current, ...row, 'server_version': ++_version};
  }

  @override
  Future<List<PushResult>> push(List<Map<String, Object?>> ops) async {
    if (offline) throw const SocketException('offline');
    pushed.add(ops);
    return [
      for (final op in ops)
        if (rejectIds.contains((op['row'] as Map)['id']))
          const PushResult(ok: false, error: 'new row violates row-level security policy')
        else
          _apply(op),
    ];
  }

  PushResult _apply(Map<String, Object?> op) {
    final row = Map<String, dynamic>.from(op['row'] as Map);
    if (op['op'] == 'delete') {
      put(op['table'] as String, {'id': row['id'], 'deleted_at': '2026-10-05T12:00:00Z'});
    } else {
      put(op['table'] as String, row);
    }
    return const PushResult(ok: true);
  }

  @override
  Future<PullPage> pull(int since, int limit) async {
    if (offline) throw const SocketException('offline');
    final changes = [
      for (final MapEntry(key: table, value: byId) in rows.entries)
        for (final row in byId.values)
          if ((row['server_version'] as int) > since) RemoteChange(table, row),
    ]..sort((a, b) => (a.row['server_version'] as int).compareTo(b.row['server_version'] as int));
    final page = changes.take(limit).toList();
    return PullPage(
      changes: page,
      cursor: page.isEmpty ? since : page.last.row['server_version'] as int,
      hasMore: changes.length > limit,
    );
  }
}

Map<String, dynamic> serverTxn(String id, {int amount = 12000, String? category}) => {
  'id': id,
  'account_id': 'acct-cbe',
  'type': 'expense',
  'amount': amount,
  'fee': 150,
  'currency': 'ETB',
  'occurred_at': '2026-10-04T08:30:00+00:00',
  'counterparty_name': 'Kaldis Coffee',
  'counterparty_kind': 'business',
  'category_id': category,
  'category_source': 'merchant_map',
  'status': 'confirmed',
  'deleted_at': null,
  'updated_at': '2026-10-04T08:31:00+00:00',
};

void main() {
  late Isar isar;
  late Directory dir;
  late FakeServer server;
  late SyncEngine engine;
  late IsarTransactionRepository txns;
  final now = DateTime.utc(2026, 10, 5, 12);

  setUpAll(initIsarForTests);

  setUp(() async {
    (isar, dir) = await openTestIsar();
    server = FakeServer();
    engine = SyncEngine(isar, server, pushBatchSize: 2, pullPageSize: 3, clock: () => now);
    txns = IsarTransactionRepository(isar, clock: () => now);
  });

  tearDown(() => closeTestIsar(isar, dir));

  test('an offline write reaches the server after reconnecting and the outbox empties', () async {
    server.offline = true;
    final t = await txns.add(accountId: 'acct-cash', type: TransactionType.expense, amount: 5000);
    await expectLater(engine.sync(), throwsA(isA<SocketException>()));
    expect(await engine.pendingCount(), 1, reason: 'nothing is lost while offline');

    server.offline = false;
    final report = await engine.sync();
    expect(report.pushed, 1);
    expect(await engine.pendingCount(), 0);
    expect(server.rows['transactions']![t.id]!['amount'], 5000);
  });

  test('push sends ops oldest first in batches', () async {
    final ids = [
      for (var i = 1; i <= 5; i++) (await txns.add(accountId: 'a', type: TransactionType.expense, amount: i)).id,
    ];
    await engine.push();
    expect(server.pushed.map((b) => b.length), [2, 2, 1]);
    expect(server.pushed.expand((b) => b).map((o) => (o['row'] as Map)['id']), ids);
  });

  test('a rejected op stays queued with the error; the rest go through', () async {
    final bad = await txns.add(accountId: 'not-mine', type: TransactionType.expense, amount: 1);
    await txns.add(accountId: 'a', type: TransactionType.expense, amount: 2);
    server.rejectIds.add(bad.id);

    final (accepted, rejected) = await engine.push();
    expect((accepted, rejected), (1, 1));
    final left = await isar.outboxOps.where().findAll();
    expect(left.single.rowId, bad.id);
    expect(left.single.attempts, 1);
    expect(left.single.lastError, contains('row-level security'));
  });

  test('a server-side change appears on the phone, across pages, and the cursor is kept', () async {
    server.put('financial_accounts', {
      'id': 'acct-cbe',
      'name': 'CBE ****1234',
      'institution': 'cbe',
      'masked_number': '****1234',
      'currency': 'ETB',
      'is_active': true,
      'deleted_at': null,
    });
    server.put('categories', {
      'id': 'cat-coffee',
      'user_id': null,
      'parent_id': 'cat-food',
      'key': 'food.coffee',
      'name': 'Coffee',
      'kind': 'expense',
      'sort_order': 3,
      'is_archived': false,
      'deleted_at': null,
    });
    server.put('profiles', {'id': 'user-1', 'display_name': 'Miko'});
    for (var i = 1; i <= 4; i++) {
      server.put('transactions', serverTxn('tx-$i', amount: i * 1000, category: 'cat-coffee'));
    }

    expect(await engine.pull(), 6, reason: 'profiles are not stored locally');
    expect((await isar.syncStates.get(0))!.cursor, 7);

    final recent = await txns.watchRecent().first;
    expect(recent.map((t) => t.id).toSet(), {'tx-1', 'tx-2', 'tx-3', 'tx-4'});
    final tx = recent.firstWhere((t) => t.id == 'tx-2');
    expect((tx.amount, tx.fee, tx.categoryId, tx.counterpartyName), (2000, 150, 'cat-coffee', 'Kaldis Coffee'));
    expect(tx.occurredAt.isAtSameMomentAs(DateTime.utc(2026, 10, 4, 8, 30)), isTrue);

    final accounts = await IsarAccountRepository(isar).watchAll().first;
    expect(accounts.single.maskedNumber, '****1234');
    final categories = await IsarCategoryRepository(isar).watchAll().first;
    expect(categories.single.key, 'food.coffee');
    expect(categories.single.isCustom, isFalse);

    // Only newer changes on the next pull.
    server.put('transactions', {'id': 'tx-1', 'deleted_at': '2026-10-05T09:00:00Z'});
    expect(await engine.pull(), 1);
    expect((await txns.watchRecent().first).map((t) => t.id), isNot(contains('tx-1')));
  });

  test('pull does not overwrite a row whose local change has not been pushed', () async {
    final t = await txns.add(accountId: 'acct-cash', type: TransactionType.expense, amount: 700);
    server.put('transactions', {...serverTxn(t.id), 'amount': 999});

    await engine.pull();
    expect((await isar.localTransactions.getByUuid(t.id))!.amount, 700);

    // Once pushed, the server echoes the accepted write back.
    await engine.sync();
    expect((await isar.localTransactions.getByUuid(t.id))!.amount, 700);
    expect((await isar.localTransactions.getByUuid(t.id))!.serverVersion, greaterThan(0));
  });

  test('a local delete is pushed and stays deleted after pull', () async {
    final t = await txns.add(accountId: 'a', type: TransactionType.expense, amount: 300);
    await engine.sync();
    await txns.delete(t.id);
    await engine.sync();
    expect(server.rows['transactions']![t.id]!['deleted_at'], isNotNull);
    expect(await txns.watchRecent().first, isEmpty);
  });

  test('sync calls made while one is running join it and run once more', () async {
    final gate = Completer<void>();
    final slow = _GatedServer(server, gate.future);
    final e = SyncEngine(isar, slow, clock: () => now);
    await txns.add(accountId: 'a', type: TransactionType.expense, amount: 1);

    final first = e.sync();
    await Future<void>.delayed(Duration.zero);
    await txns.add(accountId: 'a', type: TransactionType.expense, amount: 2);
    final second = e.sync();
    gate.complete();

    expect(identical(await first, await second), isTrue);
    expect(await e.pendingCount(), 0, reason: 'the write made mid-sync was pushed by the rerun');
  });

  test('clearLocalData wipes rows, outbox and cursor', () async {
    await txns.add(accountId: 'a', type: TransactionType.expense, amount: 1);
    server.put('transactions', serverTxn('tx-1'));
    await engine.pull();
    await clearLocalData(isar);
    expect(await isar.localTransactions.count(), 0);
    expect(await isar.outboxOps.count(), 0);
    expect(await isar.syncStates.get(0), isNull);
  });
}

class _GatedServer implements SyncApi {
  _GatedServer(this._inner, this._gate);

  final SyncApi _inner;
  final Future<void> _gate;

  @override
  Future<PullPage> pull(int since, int limit) => _inner.pull(since, limit);

  @override
  Future<List<PushResult>> push(List<Map<String, Object?>> ops) async {
    await _gate;
    return _inner.push(ops);
  }
}

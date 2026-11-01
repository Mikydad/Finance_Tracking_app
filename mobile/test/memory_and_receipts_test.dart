import 'dart:convert';
import 'dart:io';

import 'package:finance_app/data/local/models.dart';
import 'package:finance_app/data/receipts/receipt_enricher.dart';
import 'package:finance_app/data/receipts/receipt_reader.dart';
import 'package:finance_app/data/repositories/transaction_repository.dart';
import 'package:finance_app/domain/counterparty.dart';
import 'package:finance_app/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isar_community/isar.dart';

import 'isar_helper.dart';
import 'receipt_reader_test.dart' show telebirrHtml;

void main() {
  late Isar isar;
  late Directory dir;
  late IsarTransactionRepository repo;
  final now = DateTime.utc(2026, 10, 7, 12);

  setUpAll(initIsarForTests);

  setUp(() async {
    (isar, dir) = await openTestIsar();
    repo = IsarTransactionRepository(isar, clock: () => now, userId: () => 'user-1');
    await isar.writeTxn(() async {
      await isar.localSources.put(
        LocalSource()
          ..uuid = 'src-shortcut'
          ..type = 'shortcut',
      );
      await isar.localSources.put(
        LocalSource()
          ..uuid = 'src-manual'
          ..type = 'manual',
      );
      await isar.localAccounts.put(
        LocalAccount()
          ..uuid = 'acct-tb'
          ..name = 'telebirr'
          ..institution = 'telebirr',
      );
      await isar.localAccounts.put(
        LocalAccount()
          ..uuid = 'acct-cbe'
          ..name = 'CBE'
          ..institution = 'cbe',
      );
    });
  });

  tearDown(() => closeTestIsar(isar, dir));

  /// A transaction as it arrives from the server after an SMS capture.
  Future<LocalTransaction> captured(
    String id, {
    String? name,
    String? account,
    String? ref,
    String status = 'needs_review',
    String? categorySource = 'fallback',
    String? categoryId = 'cat-transfer',
    String accountId = 'acct-tb',
    String? notes,
    DateTime? at,
  }) async {
    final row = LocalTransaction()
      ..uuid = id
      ..accountId = accountId
      ..type = 'expense'
      ..amount = 50000
      ..occurredAt = at ?? now.subtract(const Duration(hours: 1))
      ..sourceId = 'src-shortcut'
      ..counterpartyName = name
      ..counterpartyAccount = account
      ..referenceId = ref
      ..status = status
      ..categorySource = categorySource
      ..categoryId = categoryId
      ..notes = notes
      ..serverVersion = 1
      ..updatedAt = now.subtract(const Duration(hours: 1));
    await isar.writeTxn(() => isar.localTransactions.put(row));
    return row;
  }

  Future<List<Map<String, dynamic>>> outbox([String? table]) async => [
    for (final o in await isar.outboxOps.where().findAll())
      if (table == null || o.table == table) jsonDecode(o.payload) as Map<String, dynamic>,
  ];

  Future<Txn> one(String id) async => (await repo.watchOne(id).first)!;

  group('counterparty keys', () {
    test('names ignore case and punctuation; accounts reduce to one shape', () {
      expect(nameKey('HANA  GIRMA.'), 'hana girma');
      expect(accountKey('1********3307'), '****3307');
      expect(accountKey('1000123453307'), '****3307');
      expect(accountKey('2519****1122'), '2519****1122');
      expect(sameCounterparty(nameA: 'Hana Girma', nameB: 'HANA GIRMA'), isTrue);
      expect(
        sameCounterparty(nameA: 'Hana', accountA: '2519****1122', nameB: 'Hana G.', accountB: '2519****1122'),
        isTrue,
      );
      expect(sameCounterparty(nameA: null, nameB: null), isFalse);
    });
  });

  group('reason', () {
    test('updateNotes saves and queues only the note; review stays', () async {
      await captured('t1', name: 'Hana Girma');
      await repo.updateNotes('t1', '  Lunch with Hana ');
      final t = await one('t1');
      expect(t.notes, 'Lunch with Hana');
      expect(t.status, TransactionStatus.needsReview);
      expect(await outbox(), [
        {'id': 't1', 'notes': 'Lunch with Hana'},
      ]);
    });

    test('clearing the field stores null; an unchanged note queues nothing', () async {
      await captured('t1', notes: 'Rent');
      await repo.updateNotes('t1', 'Rent');
      expect(await outbox(), isEmpty);
      await repo.updateNotes('t1', '   ');
      expect((await one('t1')).notes, isNull);
    });
  });

  group('receipts', () {
    test('fill only empty fields and mark the receipt read', () async {
      await captured('t1', name: 'Hana Girma', ref: 'DJ50KQ3RTA');
      await repo.applyReceipt(
        't1',
        reason: 'Overdraft',
        counterpartyName: 'Hana Girma Alemu',
        counterpartyAccount: '2519****1122',
      );
      final t = await one('t1');
      expect(t.notes, 'Overdraft');
      expect(t.counterpartyName, 'Hana Girma', reason: 'the SMS name is kept');
      expect(t.counterpartyAccount, '2519****1122');
      expect(await outbox(), [
        {'id': 't1', 'notes': 'Overdraft', 'counterparty_account': '2519****1122'},
      ]);
      expect(await repo.receiptCandidates(since: now.subtract(const Duration(days: 30))), isEmpty);
    });

    test("never overwrites the user's own reason", () async {
      await captured('t1', ref: 'DJ50KQ3RTA', notes: 'Mine');
      await repo.applyReceipt('t1', reason: 'From bank');
      expect((await one('t1')).notes, 'Mine');
    });

    test('candidates: automatic, with a reference, recent, unread', () async {
      await captured('auto', ref: 'DJ1AAAAAAA');
      await captured('no-ref');
      await captured('old', ref: 'DJ2AAAAAAA', at: now.subtract(const Duration(days: 60)));
      final manual = await captured('manual', ref: 'DJ3AAAAAAA');
      await isar.writeTxn(() => isar.localTransactions.put(manual..sourceId = 'src-manual'));

      final list = await repo.receiptCandidates(since: now.subtract(const Duration(days: 30)));
      expect(list.map((c) => (c.txn.id, c.institution)), [('auto', 'telebirr')]);
    });

    test('three failed reads give up', () async {
      await captured('t1', ref: 'DJ50KQ3RTA');
      for (var i = 0; i < 3; i++) {
        expect(await repo.receiptCandidates(since: now.subtract(const Duration(days: 1))), hasLength(1));
        await repo.receiptFailed('t1');
      }
      expect(await repo.receiptCandidates(since: now.subtract(const Duration(days: 1))), isEmpty);
    });
  });

  group('memory', () {
    test('choosing a category writes name and account rules with stable ids', () async {
      await captured('t1', name: 'Hana Girma', account: '2519****1122');
      await repo.update((await one('t1')).copyWith(categoryId: () => 'cat-family'));

      final rules = await outbox('categorization_rules');
      expect(rules.map((r) => (r['match_field'], r['match_value'], r['category_id'])), [
        ('counterparty', 'hana girma', 'cat-family'),
        ('counterparty_account', '2519****1122', 'cat-family'),
      ]);
      expect(rules.first['user_id'], 'user-1');

      // Teaching again reuses the same rule ids (the server's unique index
      // would reject a second rule for the same match).
      await repo.update((await one('t1')).copyWith(categoryId: () => 'cat-food'));
      final again = await outbox('categorization_rules');
      expect(again.sublist(2).map((r) => r['id']), rules.map((r) => r['id']));
    });

    test('no rules without a signed-in user, but local memory still works', () async {
      final local = IsarTransactionRepository(isar, clock: () => now);
      await captured('t1', name: 'Hana Girma');
      await local.update((await local.watchOne('t1').first)!.copyWith(categoryId: () => 'cat-family'));
      expect(await outbox('categorization_rules'), isEmpty);
      expect(await local.learnedCategory(name: 'HANA GIRMA'), 'cat-family');
    });

    test("teaching one sorts the same person's others waiting for review", () async {
      await captured('t1', name: 'Hana Girma');
      await captured('t2', account: '2519****1122', name: 'H. Girma');
      await captured('t3', name: 'Hana Girma', status: 'confirmed', categorySource: 'user', categoryId: 'cat-gift');
      await captured('t4', name: 'Someone Else');
      await isar.writeTxn(() async {
        final t1 = (await isar.localTransactions.getByUuid('t1'))!;
        await isar.localTransactions.put(t1..counterpartyAccount = '2519****1122');
      });

      await repo.update((await one('t1')).copyWith(categoryId: () => 'cat-family'));

      final t2 = await one('t2');
      expect(t2.categoryId, 'cat-family', reason: 'matched by account number');
      expect(t2.categorySource, 'rule');
      expect(t2.status, TransactionStatus.confirmed);
      expect((await one('t3')).categoryId, 'cat-gift', reason: "the user's own choice is never overridden");
      expect((await one('t4')).status, TransactionStatus.needsReview);
    });

    test('related: same account or name, newest first, deleted hidden', () async {
      final base = await captured('t1', name: 'Hana Girma', account: '2519****1122');
      await captured('t2', name: 'HANA GIRMA', at: now.subtract(const Duration(days: 2)));
      await captured('t3', name: 'Other name', account: '2519****1122', at: now.subtract(const Duration(days: 1)));
      await captured('t4', name: 'Someone Else');
      await captured('t5', name: 'Hana Girma');
      await repo.delete('t5');

      final related = await repo.watchRelated((await one(base.uuid))).first;
      expect(related.map((t) => t.id), ['t3', 't2']);
    });

    test('applyLearnedCategories after a receipt filled in the account', () async {
      await captured(
        'old',
        name: 'Hana Girma',
        account: '2519****1122',
        status: 'confirmed',
        categorySource: 'user',
        categoryId: 'cat-family',
      );
      await captured('new', ref: 'DJ50KQ3RTA'); // CBE-style SMS with no name
      await repo.applyReceipt('new', counterpartyAccount: '2519****1122');

      expect(await repo.applyLearnedCategories(), 1);
      final t = await one('new');
      expect(t.categoryId, 'cat-family');
      expect(t.status, TransactionStatus.confirmed);
    });
  });

  group('enricher', () {
    test('reads telebirr receipts, skips unsupported ones, then applies memory', () async {
      await captured(
        'old',
        name: 'Hana Girma Alemu',
        status: 'confirmed',
        categorySource: 'user',
        categoryId: 'cat-family',
      );
      await captured('tb', ref: 'DJ50KQ3RTA');
      await captured('branch', ref: 'FT26273XKD4P', accountId: 'acct-cbe');
      final calls = <Uri>[];
      final reader = ReceiptReader(
        client: MockClient((req) async {
          calls.add(req.url);
          return http.Response.bytes(utf8.encode(telebirrHtml()), 200);
        }),
      );

      await ReceiptEnricher(repo, reader, clock: () => now).run();

      expect(calls.map((u) => u.path), ['/receipt/DJ50KQ3RTA']);
      final tb = await one('tb');
      expect(tb.notes, 'Overdraft');
      expect(tb.counterpartyName, 'Hana Girma Alemu');
      expect(tb.categoryId, 'cat-family', reason: 'the receipt name matched a taught person');
      expect(await repo.receiptCandidates(since: now.subtract(const Duration(days: 30))), isEmpty);
    });

    test('a network failure is retried on the next run', () async {
      await captured('tb', ref: 'DJ50KQ3RTA');
      final reader = ReceiptReader(client: MockClient((_) async => throw http.ClientException('offline')));
      await ReceiptEnricher(repo, reader, clock: () => now).run();
      expect(await repo.receiptCandidates(since: now.subtract(const Duration(days: 30))), hasLength(1));
    });
  });
}

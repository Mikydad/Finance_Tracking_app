import 'package:finance_app/domain/account.dart';
import 'package:finance_app/domain/category.dart';
import 'package:finance_app/domain/transaction.dart';
import 'package:finance_app/features/export/csv_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const categories = {
    'cat-food': Category(id: 'cat-food', key: 'food', name: 'Food'),
    'cat-coffee': Category(id: 'cat-coffee', key: 'food.coffee', name: 'Coffee', parentId: 'cat-food'),
  };
  const accounts = {'acct-tb': Account(id: 'acct-tb', name: 'telebirr', institution: 'telebirr')};

  List<String> lines(String csv) => csv.substring(1).trimRight().split('\r\n');

  test('header, oldest first, plain numbers, category path, BOM for Excel', () {
    final csv = buildCsv(
      [
        Txn(
          id: 'b',
          accountId: 'acct-tb',
          type: TransactionType.income,
          amount: 4200000,
          occurredAt: DateTime(2026, 10, 7, 9, 5),
          counterpartyName: 'Salary',
        ),
        Txn(
          id: 'a',
          accountId: 'acct-tb',
          type: TransactionType.expense,
          amount: 47500,
          fee: 200,
          occurredAt: DateTime(2026, 10, 6, 21, 5),
          counterpartyName: 'Hana Girma',
          counterpartyAccount: '2519****1122',
          categoryId: 'cat-coffee',
          notes: 'Coffee beans',
          referenceId: 'DJ50KQ3RTA',
          isAutomatic: true,
          status: TransactionStatus.needsReview,
        ),
      ],
      categories,
      accounts,
    );
    expect(csv.startsWith('﻿'), isTrue);
    final rows = lines(csv);
    expect(rows.first, csvHeader.join(','));
    expect(
      rows[1],
      '2026-10-06,21:05,expense,475.00,2.00,-477.00,Hana Girma,2519****1122,Food / Coffee,telebirr,'
      'Coffee beans,,DJ50KQ3RTA,Auto,Needs review',
    );
    expect(rows[2], startsWith('2026-10-07,09:05,income,42000.00,0.00,42000.00,Salary,,'));
  });

  test('quotes commas, quotes and line breaks; blocks spreadsheet formulas', () {
    final csv = buildCsv(
      [
        Txn(
          id: 'x',
          accountId: 'acct-tb',
          type: TransactionType.expense,
          amount: 100,
          occurredAt: DateTime(2026, 10, 1),
          counterpartyName: '=HYPERLINK("x")',
          notes: 'rent, "October"\nsecond line',
        ),
      ],
      categories,
      accounts,
    );
    expect(csv, contains('"\'=HYPERLINK(""x"")"'));
    expect(csv, contains('"rent, ""October""\nsecond line"'));
  });

  test('ranges: this month and last month do not overlap', () {
    final r = exportRanges(DateTime(2026, 1, 15));
    expect(r[0].from, DateTime(2026, 1));
    expect((r[1].from, r[1].to), (DateTime(2025, 12), DateTime(2026, 1)));
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:finance_app/domain/category.dart';
import 'package:finance_app/domain/transaction.dart';
import 'package:finance_app/features/export/pdf_report.dart';
import 'package:flutter_test/flutter_test.dart';

ByteData font(String name) => ByteData.sublistView(File('assets/fonts/$name').readAsBytesSync());

void main() {
  const categories = {'biz': Category(id: 'biz', name: 'Business')};
  List<Txn> txns(int n) => [
    for (var i = 0; i < n; i++)
      Txn(
        id: 't$i',
        accountId: 'a',
        type: TransactionType.expense,
        amount: 125000 + i,
        fee: 200,
        occurredAt: DateTime(2026, 10, 1 + i % 28, 9),
        counterpartyName: i.isEven ? 'Abebe Kebede' : 'ሐና ግርማ', // Amharic needs the Ethiopic font
        categoryId: 'biz',
        notes: i.isEven ? 'Printer ink' : 'የቢሮ ኪራይ',
        referenceId: 'DJ50KQ3R${i.toString().padLeft(2, '0')}',
      ),
  ];

  Future<Uint8List> build(List<Txn> list, {bool total = false}) => buildReportPdf(
    title: 'Business expenses',
    rangeLabel: 'October 2026',
    transactions: list,
    categories: categories,
    latinFont: font('NotoSans-Regular.ttf'),
    ethiopicFont: font('NotoSansEthiopic-Regular.ttf'),
    includeTotal: total,
    generatedAt: DateTime(2026, 10, 31),
  );

  int pages(Uint8List pdf) => RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(pdf)).length;

  test('builds a valid PDF with English and Amharic text, with or without the total', () async {
    final pdf = await build(txns(3), total: true);
    expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
    expect(pages(pdf), 1);
    expect((await build(txns(3))).length, isPositive);
  });

  test('a long list flows onto more pages', () async {
    expect(pages(await build(txns(80))), greaterThan(1));
  });
}

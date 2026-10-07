import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../domain/account.dart';
import '../../domain/category.dart';
import '../../domain/transaction.dart';
import '../../providers.dart';

/// A date range to export; `from` inclusive, `to` exclusive, null = open.
typedef ExportRange = ({String label, DateTime? from, DateTime? to});

List<ExportRange> exportRanges(DateTime now) => [
  (label: 'This month', from: startOfMonth(now), to: null),
  (label: 'Last month', from: DateTime(now.year, now.month - 1), to: startOfMonth(now)),
  (label: 'Last 3 months', from: DateTime(now.year, now.month - 2), to: null),
  (label: 'This year', from: DateTime(now.year), to: null),
  (label: 'Everything', from: null, to: null),
];

const csvHeader = [
  'Date', 'Time', 'Type', 'Amount (ETB)', 'Fee (ETB)', 'Total (ETB)', 'Name', 'Their account', //
  'Category', 'Paid from', 'Reason', 'Bank says', 'Transaction ID', 'Captured', 'Status',
];

/// One row per transaction, oldest first, opening cleanly in Excel and
/// Google Sheets (amounts as plain numbers, a BOM so Amharic shows right).
String buildCsv(List<Txn> txns, Map<String, Category> categories, Map<String, Account> accounts) {
  String plain(int santim) => formatBirr(santim).replaceAll(',', '');
  String date(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  final rows = <List<String>>[csvHeader];
  for (final t in [...txns]..sort((a, b) => a.occurredAt.compareTo(b.occurredAt))) {
    final local = t.occurredAt.toLocal();
    final category = categories[t.categoryId];
    final parent = categories[category?.parentId];
    rows.add([
      date(local),
      clock(local),
      t.type.name,
      plain(t.amount),
      plain(t.fee),
      plain(t.signedTotal),
      t.counterpartyName ?? '',
      t.counterpartyAccount ?? '',
      [?parent?.name, ?category?.name].join(' / '),
      accounts[t.accountId]?.name ?? '',
      t.notes ?? '',
      t.description ?? '',
      t.referenceId ?? '',
      t.isAutomatic ? 'Auto' : 'Manual',
      switch (t.status) {
        TransactionStatus.needsReview => 'Needs review',
        TransactionStatus.pending => 'Pending',
        TransactionStatus.confirmed => 'Confirmed',
      },
    ]);
  }
  return '﻿${rows.map((r) => r.map(_cell).join(',')).join('\r\n')}\r\n';
}

String _cell(String v) {
  // Quote anything with separators; neutralize leading =,+,-,@ so a
  // spreadsheet doesn't run a name as a formula.
  var s = v;
  if ((s.isNotEmpty && '=+@'.contains(s[0])) || (s.startsWith('-') && double.tryParse(s) == null)) s = "'$s";
  return RegExp(r'[",\r\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
}

/// Asks for a range, writes the CSV to a temp file and opens the share sheet.
/// Works offline: everything comes from the phone.
Future<void> exportTransactions(BuildContext context, WidgetRef ref) async {
  final range = await showModalBottomSheet<ExportRange>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Export transactions (CSV)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          for (final r in exportRanges(DateTime.now()))
            ListTile(key: Key('export-${r.label}'), title: Text(r.label), onTap: () => Navigator.pop(context, r)),
        ],
      ),
    ),
  );
  if (range == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final box = context.findRenderObject() as RenderBox?;
  final txns = await ref.read(transactionRepositoryProvider).watch(from: range.from, to: range.to).first;
  if (txns.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text('No transactions in ${range.label.toLowerCase()}.')));
    return;
  }
  final categories = ref.read(categoryByIdProvider).value ?? const {};
  final accounts = {for (final a in ref.read(accountsProvider).value ?? const <Account>[]) a.id: a};

  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now();
  final name =
      'transactions-${range.label.toLowerCase().replaceAll(' ', '-')}-'
      '${stamp.year}${stamp.month.toString().padLeft(2, '0')}${stamp.day.toString().padLeft(2, '0')}.csv';
  final file = File('${dir.path}/$name');
  await file.writeAsString(buildCsv(txns, categories, accounts), encoding: utf8);

  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Transactions: ${range.label}',
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

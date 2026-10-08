import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../domain/account.dart';
import '../../domain/category.dart';
import '../../domain/transaction.dart';
import '../../providers.dart';
import '../insights/category_period_screen.dart';
import 'pdf_report.dart';

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

enum ExportFormat { pdf, csv }

/// Export or share transactions: pick a range, optionally one category (e.g.
/// Business), and PDF (a clean report for someone else, without your totals)
/// or CSV (for spreadsheets). Works offline: everything comes from the phone.
/// [categoryId] and [range] pre-fill the sheet (from a category in Insights).
Future<void> exportTransactions(BuildContext context, WidgetRef ref, {String? categoryId, ExportRange? range}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ExportSheet(categoryId: categoryId, range: range),
    );

class _ExportSheet extends ConsumerStatefulWidget {
  const _ExportSheet({this.categoryId, this.range});

  final String? categoryId;
  final ExportRange? range;

  @override
  ConsumerState<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<_ExportSheet> {
  late final List<ExportRange> _ranges = [?widget.range, ...exportRanges(DateTime.now())];
  late ExportRange _range = _ranges.first;
  late String? _categoryId = widget.categoryId;
  late ExportFormat _format = widget.categoryId != null ? ExportFormat.pdf : ExportFormat.csv;
  bool _includeTotal = false;
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject() as RenderBox?;
    try {
      final categories = ref.read(categoryByIdProvider).value ?? const {};
      final accounts = {for (final a in ref.read(accountsProvider).value ?? const <Account>[]) a.id: a};
      var txns = await ref.read(transactionRepositoryProvider).watch(from: _range.from, to: _range.to).first;
      if (_categoryId != null) {
        txns = [
          for (final t in txns)
            if (t.type != TransactionType.transfer && CategoryPeriodScreen.belongs(t, _categoryId, categories)) t,
        ];
      }
      if (txns.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('Nothing to export for this choice.')));
        return;
      }

      final categoryName = _categoryId == null ? null : categories[_categoryId]?.name;
      final slug = [
        categoryName ?? 'transactions',
        _range.label,
      ].join('-').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
      final dir = await getTemporaryDirectory();
      final XFile file;
      if (_format == ExportFormat.pdf) {
        final bytes = await buildReportPdf(
          title: categoryName == null ? 'Transactions' : '$categoryName expenses',
          rangeLabel: _range.label,
          transactions: txns,
          categories: categories,
          latinFont: await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
          ethiopicFont: await rootBundle.load('assets/fonts/NotoSansEthiopic-Regular.ttf'),
          includeTotal: _includeTotal,
        );
        final f = File('${dir.path}/$slug.pdf');
        await f.writeAsBytes(bytes);
        file = XFile(f.path, mimeType: 'application/pdf');
      } else {
        final f = File('${dir.path}/$slug.csv');
        await f.writeAsString(buildCsv(txns, categories, accounts), encoding: utf8);
        file = XFile(f.path, mimeType: 'text/csv');
      }
      await SharePlus.instance.share(
        ShareParams(
          files: [file],
          subject: '${categoryName ?? 'Transactions'}: ${_range.label}',
          sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = (ref.watch(categoriesProvider).value ?? const <Category>[]).where((c) => c.isTopLevel).toList();
    final known = _categoryId == null || categories.any((c) => c.id == _categoryId);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Export or share', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<ExportRange>(
              key: const Key('export-range'),
              initialValue: _range,
              decoration: const InputDecoration(labelText: 'When'),
              items: [for (final r in _ranges) DropdownMenuItem(value: r, child: Text(r.label))],
              onChanged: (r) => setState(() => _range = r ?? _range),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: const Key('export-category'),
              initialValue: known ? _categoryId : null,
              decoration: const InputDecoration(labelText: 'What'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All transactions')),
                for (final c in categories) DropdownMenuItem(value: c.id, child: Text('Only ${c.name}')),
              ],
              onChanged: (id) => setState(() => _categoryId = id),
            ),
            const SizedBox(height: 16),
            SegmentedButton<ExportFormat>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ExportFormat.pdf, label: Text('PDF report'), icon: Icon(Icons.picture_as_pdf)),
                ButtonSegment(value: ExportFormat.csv, label: Text('CSV'), icon: Icon(Icons.table_chart_outlined)),
              ],
              selected: {_format},
              onSelectionChanged: (s) => setState(() => _format = s.single),
            ),
            if (_format == ExportFormat.pdf) ...[
              SwitchListTile(
                key: const Key('export-total'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Show the total of these items'),
                subtitle: const Text('Your balance and other spending are never included.'),
                value: _includeTotal,
                onChanged: (v) => setState(() => _includeTotal = v),
              ),
            ] else
              const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('export-go'),
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.ios_share),
              label: Text(_busy ? 'Preparing…' : 'Share'),
            ),
          ],
        ),
      ),
    );
  }
}

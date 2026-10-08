import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../domain/category.dart';
import '../../domain/transaction.dart';

/// A shareable PDF of only the chosen transactions, e.g. "Business
/// expenses, October 2026", for someone who should see those items and
/// nothing else: no balances, no other spending, no overall totals. The sum
/// of the listed items is included only when asked.
Future<Uint8List> buildReportPdf({
  required String title,
  required String rangeLabel,
  required List<Txn> transactions,
  required Map<String, Category> categories,
  required ByteData latinFont,
  required ByteData ethiopicFont,
  bool includeTotal = false,
  DateTime? generatedAt,
}) async {
  final base = pw.Font.ttf(latinFont);
  final ethiopic = pw.Font.ttf(ethiopicFont);
  final doc = pw.Document(
    title: title,
    theme: pw.ThemeData.withFont(base: base, bold: base, fontFallback: [ethiopic]),
  );
  final rows = [...transactions]..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  final total = rows.fold<int>(0, (s, t) => s + (t.type == TransactionType.income ? t.amount : t.amount + t.fee));
  final muted = PdfColor.fromInt(0xFF6B7470);
  final accent = PdfColor.fromInt(0xFF0E4F3B);
  final made = generatedAt ?? DateTime.now();

  String categoryOf(Txn t) {
    final c = categories[t.categoryId];
    final parent = categories[c?.parentId];
    return [?parent?.name, ?c?.name].join(' / ');
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
      header: (context) => context.pageNumber == 1
          ? pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(title, style: pw.TextStyle(fontSize: 20, color: accent)),
                pw.SizedBox(height: 2),
                pw.Text(
                  '$rangeLabel · ${rows.length} ${rows.length == 1 ? 'item' : 'items'}',
                  style: pw.TextStyle(fontSize: 11, color: muted),
                ),
                if (includeTotal) ...[
                  pw.SizedBox(height: 8),
                  pw.Text('Total of these items: ${formatBirr(total)} ETB', style: const pw.TextStyle(fontSize: 13)),
                ],
                pw.SizedBox(height: 14),
              ],
            )
          : pw.SizedBox(),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Generated ${longDate(made)}', style: pw.TextStyle(fontSize: 8, color: muted)),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: muted),
          ),
        ],
      ),
      build: (context) => [
        pw.TableHelper.fromTextArray(
          headers: const ['Date', 'To / From', 'Reason', 'Category', 'Amount (ETB)', 'Ref'],
          data: [
            for (final t in rows)
              [
                '${shortDate(t.occurredAt)}\n${clock(t.occurredAt)}',
                t.counterpartyName ?? t.counterpartyAccount ?? '',
                t.notes ?? t.description ?? '',
                categoryOf(t),
                '${t.type == TransactionType.income ? '+' : ''}${formatBirr(t.type == TransactionType.income ? t.amount : t.amount + t.fee)}',
                t.referenceId ?? '',
              ],
          ],
          border: null,
          headerStyle: pw.TextStyle(fontSize: 9, color: PdfColors.white),
          headerDecoration: pw.BoxDecoration(color: accent),
          cellStyle: const pw.TextStyle(fontSize: 9),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F6F4)),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
          headerAlignment: pw.Alignment.centerLeft,
          cellAlignments: {4: pw.Alignment.topRight},
          columnWidths: {
            0: const pw.FixedColumnWidth(58),
            1: const pw.FlexColumnWidth(2.2),
            2: const pw.FlexColumnWidth(2.4),
            3: const pw.FlexColumnWidth(1.4),
            4: const pw.FixedColumnWidth(68),
            5: const pw.FixedColumnWidth(92),
          },
        ),
      ],
    ),
  );
  return doc.save();
}

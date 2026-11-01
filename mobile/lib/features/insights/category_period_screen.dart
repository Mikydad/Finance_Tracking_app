import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../core/money.dart';
import '../../core/periods.dart';
import '../../core/theme.dart';
import '../../domain/category.dart';
import '../../domain/transaction.dart';
import '../../providers.dart';
import '../../widgets/swipe_txn_tile.dart';
import '../export/csv_export.dart';

/// One category's transactions in a period (its sub-categories included).
/// [categoryId] null = uncategorized.
class CategoryPeriodScreen extends ConsumerWidget {
  const CategoryPeriodScreen({super.key, required this.categoryId, required this.period});

  final String? categoryId;
  final Period period;

  /// Whether [t] belongs under [categoryId], counting sub-categories.
  static bool belongs(Txn t, String? categoryId, Map<String, Category> categories) {
    if (categoryId == null) return t.categoryId == null || !categories.containsKey(t.categoryId);
    final c = categories[t.categoryId];
    return c != null && (c.id == categoryId || c.parentId == categoryId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoryByIdProvider).value ?? const {};
    final periods = ref.watch(periodsProvider);
    final all = ref.watch(periodTransactionsProvider(period)).value ?? const [];
    final list = all.where((t) => t.type != TransactionType.transfer && belongs(t, categoryId, categories)).toList();
    final total = list.fold<int>(0, (s, t) => s + (t.type == TransactionType.income ? t.amount : t.amount + t.fee));
    final name = categoryId == null ? 'Uncategorized' : categories[categoryId]?.name ?? 'Category';

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        centerTitle: true,
        actions: [
          IconButton(
            key: const Key('share-category'),
            tooltip: 'Share these',
            icon: const Icon(Icons.ios_share),
            onPressed: () => exportTransactions(
              context,
              ref,
              categoryId: categoryId,
              range: (label: periods.label(period), from: period.start, to: period.end),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            periods.label(period),
            style: const TextStyle(color: AppColors.muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            '${formatBirrCompact(total)} ETB · ${list.length} ${list.length == 1 ? 'transaction' : 'transactions'}',
            key: const Key('category-total'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            child: SlidableAutoCloseBehavior(
              child: Column(
                children: [for (final t in list) SwipeTxnTile(txn: t, categories: categories)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

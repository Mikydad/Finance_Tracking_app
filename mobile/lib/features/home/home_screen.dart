import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../domain/category.dart';
import '../../domain/transaction.dart';
import '../../providers.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/txn_tile.dart';

/// Spent this month, where it went by category, and the latest transactions.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasBackend = ref.watch(configProvider).hasBackend;
    final txns = ref.watch(lastTwoMonthsProvider);
    final categories = ref.watch(categoryByIdProvider).value ?? const {};
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(toolbarHeight: 72, title: Text(_greeting(now), style: Theme.of(context).textTheme.headlineSmall)),
      body: RefreshIndicator(
        onRefresh: () => _refresh(context, ref),
        notificationPredicate: (_) => hasBackend,
        child: txns.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load transactions: $e')),
          data: (list) {
            final summary = MonthSummary.of(list, now, categories);
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                if (!hasBackend)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'No backend configured: data stays on this device.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ),
                _SpentCard(summary: summary, now: now),
                const SizedBox(height: 20),
                if (summary.byCategory.isNotEmpty) ...[
                  Text('${monthName(now.month)} ${now.year}', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          for (final row in summary.byCategory.take(5))
                            _CategoryBar(row: row, total: summary.spent, categories: categories),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                Row(
                  children: [
                    Expanded(child: Text('Recent transactions', style: Theme.of(context).textTheme.titleMedium)),
                    TextButton(onPressed: () => context.go('/transactions'), child: const Text('See all')),
                  ],
                ),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text('No transactions yet. Tap + to add one.', style: TextStyle(color: AppColors.muted)),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (final t in list.take(5))
                          TxnTile(txn: t, categories: categories, onTap: () => context.push('/transactions/${t.id}')),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _greeting(DateTime now) => switch (now.hour) {
    < 12 => 'Good morning',
    < 18 => 'Good afternoon',
    _ => 'Good evening',
  };
}

Future<void> _refresh(BuildContext context, WidgetRef ref) async {
  final scheduler = ref.read(syncSchedulerProvider);
  if (scheduler == null || await scheduler.syncNow()) return;
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("Couldn't sync. Will retry when you're back online.")));
  }
}

/// Money spent this month (expenses and fees, not income or transfers),
/// last month for comparison, and this month by top-level category.
class MonthSummary {
  const MonthSummary({required this.spent, required this.lastMonth, required this.byCategory});

  factory MonthSummary.of(List<Txn> txns, DateTime now, Map<String, Category> categories) {
    final thisMonth = startOfMonth(now);
    final lastMonthStart = DateTime(now.year, now.month - 1);
    var spent = 0, last = 0;
    final byCategory = <String?, int>{};
    for (final t in txns) {
      if (t.type != TransactionType.expense) continue;
      final cost = t.amount + t.fee;
      if (!t.occurredAt.isBefore(thisMonth)) {
        spent += cost;
        // Roll children up to their top-level category.
        final c = categories[t.categoryId];
        final root = c?.parentId ?? c?.id;
        byCategory[root] = (byCategory[root] ?? 0) + cost;
      } else if (!t.occurredAt.isBefore(lastMonthStart)) {
        last += cost;
      }
    }
    final rows = [for (final e in byCategory.entries) (categoryId: e.key, amount: e.value)]
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return MonthSummary(spent: spent, lastMonth: last, byCategory: rows);
  }

  final int spent;
  final int lastMonth;
  final List<({String? categoryId, int amount})> byCategory;

  /// Percent change from last month, or null when there's nothing to compare.
  int? get changePercent => lastMonth == 0 ? null : ((spent - lastMonth) * 100 / lastMonth).round();
}

class _SpentCard extends StatelessWidget {
  const _SpentCard({required this.summary, required this.now});

  final MonthSummary summary;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = summary.changePercent;
    final lastMonthName = monthName(DateTime(now.year, now.month - 1).month);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppRadii.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Spent this month', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.primary)),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: formatBirrCompact(summary.spent), style: theme.textTheme.headlineMedium),
                TextSpan(text: ' ETB', style: theme.textTheme.titleMedium),
              ],
            ),
            key: const Key('spent'),
          ),
          if (change != null) ...[
            const SizedBox(height: 4),
            Text(
              '${change >= 0 ? '↑' : '↓'} ${change.abs()}% vs $lastMonthName',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.primary),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.row, required this.total, required this.categories});

  final ({String? categoryId, int amount}) row;
  final int total;
  final Map<String, Category> categories;

  @override
  Widget build(BuildContext context) {
    final category = categories[row.categoryId];
    final share = total == 0 ? 0.0 : row.amount / total;
    final color = category == null
        ? CategoryStyle.uncategorized.color
        : CategoryStyle.of(key: category.key, icon: category.icon, color: category.color).color;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          CategoryIcon(category, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(category?.name ?? 'Uncategorized')),
                    Text('${formatBirrCompact(row.amount)} ETB', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: share,
                          minHeight: 6,
                          color: color,
                          backgroundColor: AppColors.background,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 36,
                      child: Text(
                        '${(share * 100).round()}%',
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

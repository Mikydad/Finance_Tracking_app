import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../domain/transaction.dart';
import '../../providers.dart';
import '../../widgets/txn_tile.dart';
import 'delete_with_undo.dart';

/// History grouped by day, with All / Expenses / Income / Transfers filters.
/// Swipe left to delete.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  TransactionType? _filter;

  static const _filters = <(String, TransactionType?)>[
    ('All', null),
    ('Expenses', TransactionType.expense),
    ('Income', TransactionType.income),
    ('Transfers', TransactionType.transfer),
  ];

  @override
  Widget build(BuildContext context) {
    final txns = ref.watch(transactionsProvider(_filter));
    final categories = ref.watch(categoryByIdProvider).value ?? const {};

    return Scaffold(
      appBar: AppBar(title: Text('Transactions', style: Theme.of(context).textTheme.headlineSmall)),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final (label, type) in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _filter == type,
                      labelStyle: TextStyle(color: _filter == type ? Colors.white : AppColors.text),
                      onSelected: (_) => setState(() => _filter = type),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: txns.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load transactions: $e')),
              data: (list) {
                if (list.isEmpty) {
                  return const Center(
                    child: Text('Nothing here yet. Tap + to add one.', style: TextStyle(color: AppColors.muted)),
                  );
                }
                final rows = _groupByDay(list);
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => switch (rows[i]) {
                    DateTime day => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(dayLabel(day), style: Theme.of(context).textTheme.titleSmall),
                    ),
                    Txn t => Dismissible(
                      key: ValueKey(t.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        color: AppColors.danger,
                        child: const Icon(Icons.delete_outline, color: Colors.white),
                      ),
                      onDismissed: (_) => deleteWithUndo(context, ref, t.id),
                      child: TxnTile(
                        txn: t,
                        categories: categories,
                        onTap: () => context.push('/transactions/${t.id}'),
                      ),
                    ),
                    _ => const SizedBox.shrink(),
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Day headers (DateTime) followed by that day's transactions (Txn).
  static List<Object> _groupByDay(List<Txn> list) {
    final rows = <Object>[];
    DateTime? current;
    for (final t in list) {
      final day = dayOf(t.occurredAt);
      if (day != current) {
        rows.add(day);
        current = day;
      }
      rows.add(t);
    }
    return rows;
  }
}

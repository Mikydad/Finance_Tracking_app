import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../domain/transaction.dart';
import '../../providers.dart';
import '../../widgets/swipe_txn_tile.dart';

/// Everything with one person or shop: the transaction [id] and every other
/// one matched to it by account number or name.
class RelatedScreen extends ConsumerWidget {
  const RelatedScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txn = ref.watch(transactionProvider(id)).value;
    final related = ref.watch(relatedTransactionsProvider(id)).value ?? const [];
    final categories = ref.watch(categoryByIdProvider).value ?? const {};
    final all = [?txn, ...related]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    final out = all.where((t) => t.type != TransactionType.income).fold<int>(0, (s, t) => s + t.amount + t.fee);
    final inn = all.where((t) => t.type == TransactionType.income).fold<int>(0, (s, t) => s + t.amount);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(txn?.counterpartyName ?? txn?.counterpartyAccount ?? 'History'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(child: _Stat('${all.length}', all.length == 1 ? 'transaction' : 'transactions')),
                  Expanded(child: _Stat('${formatBirrCompact(out)} ETB', 'paid out')),
                  if (inn > 0) Expanded(child: _Stat('${formatBirrCompact(inn)} ETB', 'received')),
                ],
              ),
            ),
          ),
          if (txn?.counterpartyAccount != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
              child: Text(
                'Account ${txn!.counterpartyAccount}',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: SlidableAutoCloseBehavior(
              child: Column(
                children: [for (final t in all) SwipeTxnTile(txn: t, categories: categories)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      ],
    );
  }
}

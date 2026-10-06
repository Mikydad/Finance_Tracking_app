import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../domain/transaction.dart';
import '../../providers.dart';
import '../../widgets/category_icon.dart';
import 'delete_with_undo.dart';

class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txn = ref.watch(transactionProvider(id));
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction'), centerTitle: true),
      body: txn.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (t) => t == null ? const Center(child: Text('This transaction was deleted.')) : _Details(t),
      ),
    );
  }
}

class _Details extends ConsumerWidget {
  const _Details(this.t);

  final Txn t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final categories = ref.watch(categoryByIdProvider).value ?? const {};
    final accounts = ref.watch(accountsProvider).value ?? const [];
    final category = categories[t.categoryId];
    final account = accounts.where((a) => a.id == t.accountId).firstOrNull;
    final total = t.signedTotal;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Center(child: CategoryIcon(category, parent: categories[category?.parentId], size: 56)),
        const SizedBox(height: 16),
        Center(
          child: Text(
            '${total >= 0 ? '+' : '-'}${formatBirrCompact(total.abs())} ${t.currency}',
            style: theme.textTheme.headlineMedium?.copyWith(color: total >= 0 ? AppColors.income : null),
          ),
        ),
        Center(child: Text(t.title, style: theme.textTheme.titleMedium)),
        const SizedBox(height: 12),
        if (t.isAutomatic) const Center(child: _Badge('Automatically detected', Icons.check_circle_outline)),
        if (t.status == TransactionStatus.needsReview)
          const Center(child: _Badge('Needs a quick look', Icons.help_outline, warning: true)),
        const SizedBox(height: 20),
        Card(
          child: Column(
            children: [
              _Row('Category', category?.name ?? 'Uncategorized'),
              _Row('Date', longDate(t.occurredAt)),
              _Row('Time', clock(t.occurredAt)),
              if (account != null) _Row('Payment source', account.name),
              if (t.fee > 0) _Row('Fee', '${formatBirr(t.fee)} ${t.currency}'),
              if (t.description != null) _Row('Bank says', t.description!),
              if (t.referenceId != null)
                _Row(
                  'Transaction ID',
                  t.referenceId!,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: t.referenceId!));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction ID copied')));
                  },
                ),
              if (t.notes != null) _Row('Notes', t.notes!),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('edit'),
          onPressed: () => context.push('/transactions/${t.id}/edit'),
          child: const Text('Edit transaction'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('delete'),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
          onPressed: () async {
            await deleteWithUndo(context, ref, t.id);
            if (context.mounted) context.pop();
          },
          child: const Text('Delete transaction'),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      title: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
      trailing: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(value, textAlign: TextAlign.end, overflow: TextOverflow.ellipsis),
            ),
            if (onTap != null) ...[const SizedBox(width: 6), const Icon(Icons.copy, size: 16, color: AppColors.muted)],
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.icon, {this.warning = false});

  final String label;
  final IconData icon;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? const Color(0xFFB7791F) : AppColors.income;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: warning ? const Color(0xFFFFF1D6) : AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 13)),
        ],
      ),
    );
  }
}

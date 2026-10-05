import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/money.dart';
import '../../domain/transaction.dart';
import '../../providers.dart';

/// Placeholder home: recent transactions from the local database. The real
/// home screen (PRD Section 16) comes in Phase 6.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasBackend = ref.watch(configProvider).hasBackend;
    final txns = ref.watch(recentTransactionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recent'),
        actions: [
          if (hasBackend)
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () => Supabase.instance.client.auth.signOut(),
            ),
        ],
      ),
      body: Column(
        children: [
          if (!hasBackend)
            const MaterialBanner(
              content: Text('No backend configured: data stays on this device.'),
              actions: [SizedBox.shrink()],
            ),
          Expanded(
            child: txns.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load transactions: $e')),
              data: (list) => list.isEmpty
                  ? const Center(child: Text('No transactions yet'))
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) => _TxnTile(list[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TxnTile extends StatelessWidget {
  const _TxnTile(this.txn);

  final Txn txn;

  @override
  Widget build(BuildContext context) {
    final total = txn.signedTotal;
    return ListTile(
      title: Text(txn.counterpartyName ?? (txn.type == TransactionType.income ? 'Income' : 'Expense')),
      subtitle: Text(MaterialLocalizations.of(context).formatMediumDate(txn.occurredAt)),
      trailing: Text(
        '${total >= 0 ? '+' : ''}${formatBirr(total)} ${txn.currency}',
        style: TextStyle(color: total >= 0 ? Colors.green.shade700 : null),
      ),
    );
  }
}

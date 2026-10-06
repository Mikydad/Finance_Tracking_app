import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/money.dart';
import '../../data/sync/sync_engine.dart';
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
            IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: () => _signOut(context, ref)),
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
              data: (list) => RefreshIndicator(
                onRefresh: () => _refresh(context, ref),
                notificationPredicate: (_) => hasBackend,
                child: list.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 160),
                          Center(child: Text('No transactions yet')),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) => _TxnTile(list[i]),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _refresh(BuildContext context, WidgetRef ref) async {
  final scheduler = ref.read(syncSchedulerProvider);
  if (scheduler == null || await scheduler.syncNow()) return;
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("Couldn't sync. Will retry when you're back online.")));
  }
}

/// Pushes what it can, warns about changes that would be lost, then signs out
/// and clears the phone so the next account starts empty.
Future<void> _signOut(BuildContext context, WidgetRef ref) async {
  // Read everything up front: signing out unmounts this screen, and `ref`
  // can't be used after that.
  final isar = ref.read(isarProvider);
  final scheduler = ref.read(syncSchedulerProvider);
  final engine = ref.read(syncEngineProvider);

  await scheduler?.syncNow();
  final unsynced = await engine?.pendingCount() ?? 0;
  if (unsynced > 0 && context.mounted) {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          '$unsynced change${unsynced == 1 ? " hasn't" : "s haven't"} reached the server yet '
          'and will be lost if you sign out now.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (proceed != true) return;
  }
  // Sign out first so no sync can write between the wipe and sign-out.
  await Supabase.instance.client.auth.signOut();
  await clearLocalData(isar);
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

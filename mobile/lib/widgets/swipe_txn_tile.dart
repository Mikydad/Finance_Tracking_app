import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../domain/category.dart';
import '../domain/transaction.dart';
import '../features/transactions/delete_with_undo.dart';
import 'txn_tile.dart';

/// A transaction row that swipes left to show Edit and Delete. A full swipe
/// deletes straight away (with Undo); a tap opens the details.
class SwipeTxnTile extends ConsumerWidget {
  const SwipeTxnTile({super.key, required this.txn, required this.categories});

  final Txn txn;
  final Map<String, Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Slidable(
      key: ValueKey(txn.id),
      groupTag: 'transactions', // opening one row closes the others
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.5,
        // A full swipe (past 60% of the row, like iPhone Mail) deletes.
        dismissible: DismissiblePane(dismissThreshold: 0.6, onDismissed: () => deleteWithUndo(context, ref, txn.id)),
        children: [
          SlidableAction(
            key: Key('edit-${txn.id}'),
            onPressed: (_) => context.push('/transactions/${txn.id}/edit'),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            icon: Icons.edit_outlined,
            label: 'Edit',
          ),
          SlidableAction(
            key: Key('delete-${txn.id}'),
            onPressed: (_) => deleteWithUndo(context, ref, txn.id),
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline,
            label: 'Delete',
          ),
        ],
      ),
      child: TxnTile(txn: txn, categories: categories, onTap: () => context.push('/transactions/${txn.id}')),
    );
  }
}

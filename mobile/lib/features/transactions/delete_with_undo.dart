import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';

/// Soft-deletes a transaction and offers Undo for a few seconds.
Future<void> deleteWithUndo(BuildContext context, WidgetRef ref, String id) async {
  final repo = ref.read(transactionRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  await repo.delete(id);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Text('Transaction deleted'),
        action: SnackBarAction(label: 'Undo', onPressed: () => repo.restore(id)),
      ),
    );
}

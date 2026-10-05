import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'data/repositories/transaction_repository.dart';
import 'domain/transaction.dart';

/// Overridden in main() once the app has started.
final configProvider = Provider<AppConfig>((ref) => throw UnimplementedError('configProvider not overridden'));
final isarProvider = Provider<Isar>((ref) => throw UnimplementedError('isarProvider not overridden'));

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => IsarTransactionRepository(ref.watch(isarProvider)),
);

final recentTransactionsProvider = StreamProvider<List<Txn>>(
  (ref) => ref.watch(transactionRepositoryProvider).watchRecent(),
);

/// Signed-in session, or null. Always null when no backend is configured.
final sessionProvider = StreamProvider<Session?>((ref) {
  if (!ref.watch(configProvider).hasBackend) return Stream.value(null);
  final auth = Supabase.instance.client.auth;
  return auth.onAuthStateChange.map((e) => e.session);
});

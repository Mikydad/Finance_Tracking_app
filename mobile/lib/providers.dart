import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/periods.dart';
import 'data/local/models.dart';
import 'data/receipts/receipt_enricher.dart';
import 'data/receipts/receipt_reader.dart';
import 'data/remote/capture_api.dart';
import 'data/repositories/account_repository.dart';
import 'data/repositories/category_repository.dart';
import 'data/repositories/goal_repository.dart';
import 'data/repositories/prefs_repository.dart';
import 'data/repositories/transaction_repository.dart';
import 'data/sync/sync_api.dart';
import 'data/sync/sync_engine.dart';
import 'data/sync/sync_scheduler.dart';
import 'domain/account.dart';
import 'domain/category.dart';
import 'domain/goal.dart';
import 'domain/transaction.dart';
import 'features/goals/goal_progress.dart';

/// Overridden in main() once the app has started.
final configProvider = Provider<AppConfig>((ref) => throw UnimplementedError('configProvider not overridden'));
final isarProvider = Provider<Isar>((ref) => throw UnimplementedError('isarProvider not overridden'));

final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  final hasBackend = ref.watch(configProvider).hasBackend;
  return IsarTransactionRepository(
    ref.watch(isarProvider),
    userId: () => hasBackend ? Supabase.instance.client.auth.currentUser?.id : null,
  );
});
final accountRepositoryProvider = Provider<AccountRepository>((ref) => IsarAccountRepository(ref.watch(isarProvider)));
final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => IsarCategoryRepository(ref.watch(isarProvider)),
);

final recentTransactionsProvider = StreamProvider<List<Txn>>(
  (ref) => ref.watch(transactionRepositoryProvider).watchRecent(),
);

/// All transactions, or only one type (the Transactions screen filter).
final transactionsProvider = StreamProvider.family<List<Txn>, TransactionType?>(
  (ref, type) => ref.watch(transactionRepositoryProvider).watch(type: type),
);

/// Transactions from the start of last month on (in the chosen calendar),
/// for this-month totals and the comparison with last month.
final lastTwoMonthsProvider = StreamProvider<List<Txn>>((ref) {
  final periods = ref.watch(periodsProvider);
  final lastMonth = periods.shift(periods.containing(PeriodKind.month, DateTime.now()), -1);
  return ref.watch(transactionRepositoryProvider).watch(from: lastMonth.start);
});

final goalRepositoryProvider = Provider<GoalRepository>((ref) {
  final hasBackend = ref.watch(configProvider).hasBackend;
  return GoalRepository(
    ref.watch(isarProvider),
    userId: () => hasBackend ? Supabase.instance.client.auth.currentUser?.id : null,
  );
});

final goalsProvider = StreamProvider<List<Goal>>((ref) => ref.watch(goalRepositoryProvider).watchActive());

/// Every active goal with where it stands this week or month.
final goalProgressProvider = Provider<AsyncValue<List<GoalProgress>>>((ref) {
  final goals = ref.watch(goalsProvider);
  final txns = ref.watch(lastTwoMonthsProvider);
  final periods = ref.watch(periodsProvider);
  final categories = ref.watch(categoryByIdProvider).value ?? const {};
  return goals.whenData((list) {
    final rows = txns.value ?? const <Txn>[];
    final now = DateTime.now();
    return [for (final g in list) GoalProgress.of(g, rows, periods, categories, now)];
  });
});

final prefsRepositoryProvider = Provider<PrefsRepository>((ref) => PrefsRepository(ref.watch(isarProvider)));

/// Calendar (Gregorian or Ethiopian) and week start, chosen in Settings.
final calendarPrefsProvider = StreamProvider<CalendarPrefs>((ref) => ref.watch(prefsRepositoryProvider).watch());

final periodsProvider = Provider<Periods>(
  (ref) => Periods(ref.watch(calendarPrefsProvider).value ?? const CalendarPrefs()),
);

/// Live transactions inside one day, week or month.
final periodTransactionsProvider = StreamProvider.family<List<Txn>, Period>(
  (ref, p) => ref.watch(transactionRepositoryProvider).watch(from: p.start, to: p.end),
);

final transactionProvider = StreamProvider.family<Txn?, String>(
  (ref, id) => ref.watch(transactionRepositoryProvider).watchOne(id),
);

/// Other transactions with the same person or shop as transaction [id].
final relatedTransactionsProvider = StreamProvider.family<List<Txn>, String>((ref, id) async* {
  final txn = await ref.watch(transactionProvider(id).future);
  if (txn == null) {
    yield const [];
    return;
  }
  yield* ref.watch(transactionRepositoryProvider).watchRelated(txn);
});

final accountsProvider = StreamProvider<List<Account>>((ref) => ref.watch(accountRepositoryProvider).watchAll());

/// Categories that can be picked (not archived).
final categoriesProvider = StreamProvider<List<Category>>((ref) => ref.watch(categoryRepositoryProvider).watchAll());

/// Every category by id, archived ones included, for showing transactions.
final categoryByIdProvider = StreamProvider<Map<String, Category>>(
  (ref) => ref
      .watch(categoryRepositoryProvider)
      .watchAll(includeArchived: true)
      .map((list) => {for (final c in list) c.id: c}),
);

/// Signed-in session, or null. Always null when no backend is configured.
final sessionProvider = StreamProvider<Session?>((ref) {
  if (!ref.watch(configProvider).hasBackend) return Stream.value(null);
  final auth = Supabase.instance.client.auth;
  return auth.onAuthStateChange.map((e) => e.session);
});

/// Sending bank SMS to the server; null when running without a backend.
final captureApiProvider = Provider<CaptureApi?>(
  (ref) => ref.watch(configProvider).hasBackend ? SupabaseCaptureApi(Supabase.instance.client) : null,
);

/// The Shortcut's active keys.
final ingestionTokensProvider = FutureProvider<List<IngestionToken>>(
  (ref) async => await ref.watch(captureApiProvider)?.tokens() ?? const [],
);

/// Null when running without a backend.
final syncEngineProvider = Provider<SyncEngine?>((ref) {
  if (!ref.watch(configProvider).hasBackend) return null;
  return SyncEngine(ref.watch(isarProvider), SupabaseSyncApi(Supabase.instance.client));
});

/// Keeps the phone in sync while someone is signed in: on start, after local
/// writes, on Realtime nudges and whenever the app comes back to the
/// foreground. Null when signed out or without a backend.
final syncSchedulerProvider = Provider<SyncScheduler?>((ref) {
  final engine = ref.watch(syncEngineProvider);
  final userId = ref.watch(sessionProvider.select((s) => s.value?.user.id));
  if (engine == null || userId == null) return null;

  final isar = ref.watch(isarProvider);
  final client = Supabase.instance.client;
  final nudges = StreamController<void>.broadcast();
  final channel = client
      .channel('sync:$userId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'transactions',
        callback: (_) => nudges.add(null),
      )
      .subscribe();

  final reader = ReceiptReader();
  final enricher = ReceiptEnricher(ref.watch(transactionRepositoryProvider), reader);
  final scheduler = SyncScheduler(
    engine,
    localChanges: newOutboxOps(isar),
    remoteChanges: nudges.stream,
    onSynced: enricher.run,
  )..start();
  final lifecycle = AppLifecycleListener(onResume: scheduler.syncNow);

  ref.onDispose(() {
    lifecycle.dispose();
    scheduler.dispose();
    reader.close();
    unawaited(client.removeChannel(channel));
    nudges.close();
  });
  return scheduler;
});

/// Fires when the outbox has ops that haven't been tried yet, and not for the
/// bookkeeping a push itself does (removing or marking ops).
Stream<void> newOutboxOps(Isar isar) => isar.outboxOps.watchLazy().asyncExpand((_) async* {
  if (await isar.outboxOps.filter().attemptsEqualTo(0).count() > 0) yield null;
});

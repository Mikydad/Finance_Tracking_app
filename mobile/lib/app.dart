import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/categories/categories_screen.dart';
import 'features/home/home_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/transactions/add_transaction_screen.dart';
import 'features/transactions/transaction_detail_screen.dart';
import 'features/transactions/transactions_screen.dart';
import 'providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final hasBackend = ref.watch(configProvider).hasBackend;
  final auth = ValueNotifier<bool>(false);
  ref.listen(sessionProvider, (_, next) => auth.value = next.value != null, fireImmediately: true);
  ref.onDispose(auth.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: auth,
    redirect: (context, state) {
      // Without a backend the app runs local-only, with no sign-in.
      if (!hasBackend) return state.matchedLocation == '/sign-in' ? '/' : null;
      final signingIn = state.matchedLocation == '/sign-in';
      if (!auth.value) return signingIn ? null : '/sign-in';
      return signingIn ? '/' : null;
    },
    routes: [
      ShellRoute(
        builder: (_, state, child) => AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (_, _) => const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: '/transactions',
            pageBuilder: (_, _) => const NoTransitionPage(child: TransactionsScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (_, _) => const NoTransitionPage(child: SettingsScreen()),
          ),
        ],
      ),
      GoRoute(
        path: '/add',
        pageBuilder: (_, _) => const MaterialPage(fullscreenDialog: true, child: AddTransactionScreen()),
      ),
      GoRoute(
        path: '/transactions/:id',
        builder: (_, state) => TransactionDetailScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/transactions/:id/edit',
        builder: (_, state) => EditTransactionRoute(id: state.pathParameters['id']!),
      ),
      GoRoute(path: '/categories', builder: (_, _) => const CategoriesScreen()),
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
    ],
  );
});

class FinanceApp extends ConsumerWidget {
  const FinanceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps background sync running while someone is signed in.
    ref.watch(syncSchedulerProvider);
    return MaterialApp.router(title: 'Finance', theme: buildAppTheme(), routerConfig: ref.watch(routerProvider));
  }
}

/// Loads the transaction, then shows the add screen in edit mode.
class EditTransactionRoute extends ConsumerWidget {
  const EditTransactionRoute({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(transactionProvider(id))
        .when(
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(body: Center(child: Text('Could not load: $e'))),
          data: (t) => t == null
              ? const Scaffold(body: Center(child: Text('This transaction was deleted.')))
              : AddTransactionScreen(existing: t),
        );
  }
}

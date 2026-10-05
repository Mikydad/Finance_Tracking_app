import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/sign_in_screen.dart';
import 'features/home/home_screen.dart';
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
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
    ],
  );
});

class FinanceApp extends ConsumerWidget {
  const FinanceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Finance',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1B6E4E), useMaterial3: true),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

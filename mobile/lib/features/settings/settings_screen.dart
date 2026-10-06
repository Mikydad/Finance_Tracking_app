import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../data/sync/sync_engine.dart';
import '../../providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasBackend = ref.watch(configProvider).hasBackend;
    final email = ref.watch(sessionProvider).value?.user.email;

    return Scaffold(
      appBar: AppBar(title: Text('Settings', style: Theme.of(context).textTheme.headlineSmall)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.primarySoft,
                child: Icon(Icons.person_outline, color: AppColors.primary),
              ),
              title: Text(email ?? 'This device only'),
              subtitle: Text(hasBackend ? 'Synced with your account' : 'No backend configured'),
            ),
          ),
          const SizedBox(height: 16),
          if (hasBackend) ...[
            Text('Transaction sources', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ListTile(
                    key: const Key('shortcut-setup'),
                    leading: const Icon(Icons.bolt_outlined),
                    title: const Text('iPhone Shortcut'),
                    subtitle: Text(switch (ref.watch(ingestionTokensProvider).value) {
                      null => ' ',
                      [] => 'Not set up',
                      final keys => keys.any((k) => k.lastUsedAt != null) ? 'Connected' : 'Key created, not used yet',
                    }),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/settings/shortcut'),
                  ),
                  ListTile(
                    key: const Key('paste-sms'),
                    leading: const Icon(Icons.sms_outlined),
                    title: const Text('Paste bank SMS'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/paste'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Card(
            child: Column(
              children: [
                ListTile(
                  key: const Key('manage-categories'),
                  leading: const Icon(Icons.grid_view_outlined),
                  title: const Text('Manage categories'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/categories'),
                ),
                const ListTile(
                  leading: Icon(Icons.payments_outlined),
                  title: Text('Currency'),
                  trailing: Text('Ethiopian Birr (ETB)', style: TextStyle(color: AppColors.muted)),
                ),
              ],
            ),
          ),
          if (hasBackend) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                key: const Key('sign-out'),
                leading: const Icon(Icons.logout, color: AppColors.danger),
                title: const Text('Sign out', style: TextStyle(color: AppColors.danger)),
                onTap: () => _signOut(context, ref),
              ),
            ),
          ],
        ],
      ),
    );
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

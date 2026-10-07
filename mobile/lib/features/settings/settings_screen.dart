import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/periods.dart';
import '../../core/theme.dart';
import '../../data/sync/sync_engine.dart';
import '../export/csv_export.dart';
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
                ListTile(
                  key: const Key('goals'),
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Goals'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/goals'),
                ),
                ListTile(
                  key: const Key('export-csv'),
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Export transactions'),
                  subtitle: const Text('CSV for Excel or Google Sheets'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => exportTransactions(context, ref),
                ),
                _CalendarSettings(),
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

/// Calendar (Gregorian or Ethiopian months) and the first day of the week,
/// used by Home, Insights and goals. Saved on this phone.
class _CalendarSettings extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(calendarPrefsProvider).value ?? const CalendarPrefs();
    final repo = ref.read(prefsRepositoryProvider);
    return Column(
      children: [
        ListTile(
          key: const Key('calendar'),
          leading: const Icon(Icons.calendar_month_outlined),
          title: const Text('Calendar'),
          trailing: DropdownButton<CalendarKind>(
            value: prefs.calendar,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: CalendarKind.gregorian, child: Text('Gregorian')),
              DropdownMenuItem(value: CalendarKind.ethiopian, child: Text('Ethiopian')),
            ],
            onChanged: (c) =>
                c == null ? null : repo.save(CalendarPrefs(calendar: c, weekStartsMonday: prefs.weekStartsMonday)),
          ),
        ),
        ListTile(
          key: const Key('week-start'),
          leading: const Icon(Icons.view_week_outlined),
          title: const Text('Week starts on'),
          trailing: DropdownButton<bool>(
            value: prefs.weekStartsMonday,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: true, child: Text('Monday')),
              DropdownMenuItem(value: false, child: Text('Sunday')),
            ],
            onChanged: (monday) =>
                monday == null ? null : repo.save(CalendarPrefs(calendar: prefs.calendar, weekStartsMonday: monday)),
          ),
        ),
      ],
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

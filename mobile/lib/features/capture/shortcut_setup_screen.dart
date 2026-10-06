import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../data/remote/capture_api.dart';
import '../../providers.dart';

/// Sets up automatic capture: a key for the iPhone Shortcut, then the steps
/// to build a Shortcuts automation that sends each bank SMS to the server.
class ShortcutSetupScreen extends ConsumerStatefulWidget {
  const ShortcutSetupScreen({super.key});

  @override
  ConsumerState<ShortcutSetupScreen> createState() => _ShortcutSetupScreenState();
}

class _ShortcutSetupScreenState extends ConsumerState<ShortcutSetupScreen> {
  /// Shown once, right after it is created.
  String? _newKey;
  bool _busy = false;
  String? _error;

  Future<void> _createKey() async {
    final api = ref.read(captureApiProvider);
    if (api == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final key = await api.createToken('iPhone Shortcut');
      if (mounted) setState(() => _newKey = key);
      ref.invalidate(ingestionTokensProvider);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't create a key. Check your connection and try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(IngestionToken token) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn off this key?'),
        content: const Text('A Shortcut using it will stop adding transactions until you give it a new key.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Turn off')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(captureApiProvider)?.revokeToken(token.id);
    ref.invalidate(ingestionTokensProvider);
  }

  void _copy(String value, String what) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what copied')));
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);
    final tokens = ref.watch(ingestionTokensProvider);
    final url = '${config.supabaseUrl}/functions/v1/ingest';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('iPhone Shortcut'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text(
            'An iPhone automation sends each bank or telebirr SMS to your account as it arrives, '
            "so transactions appear here without typing. It's two steps.",
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 20),
          Text('1. Create a key', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_newKey != null)
            Card(
              key: const Key('new-key'),
              color: AppColors.primarySoft,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Your key. Copy it now; it won\'t be shown again.'),
                    const SizedBox(height: 8),
                    SelectableText(_newKey!, style: const TextStyle(fontFamily: 'Courier', fontSize: 13)),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      key: const Key('copy-key'),
                      onPressed: () => _copy('Bearer $_newKey', 'Key'),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy "Bearer" + key for the Shortcut'),
                    ),
                  ],
                ),
              ),
            ),
          tokens.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
            error: (_, _) => const Text("Couldn't load your keys.", style: TextStyle(color: AppColors.danger)),
            data: (list) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (list.isNotEmpty)
                  Card(
                    child: Column(
                      children: [
                        for (final t in list)
                          ListTile(
                            leading: const Icon(Icons.key_outlined),
                            title: Text(t.name),
                            subtitle: Text(
                              t.lastUsedAt == null
                                  ? 'Created ${longDate(t.createdAt.toLocal())} · not used yet'
                                  : 'Last used ${dayLabel(t.lastUsedAt!.toLocal())} at ${clock(t.lastUsedAt!.toLocal())}',
                            ),
                            trailing: TextButton(onPressed: () => _revoke(t), child: const Text('Turn off')),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('create-key'),
                  onPressed: _busy ? null : _createKey,
                  icon: const Icon(Icons.add),
                  label: Text(list.isEmpty ? 'Create key' : 'Create another key'),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 28),
          Text('2. Build the automation', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _Step(1, 'Open the Shortcuts app, tap Automation, then the + button, and choose Message.'),
          const _Step(2, 'Under "Message Contains" type ETB. Optionally pick the senders: 127, CBE, CBO, BOA.'),
          const _Step(3, 'Choose "Run Immediately", turn off "Notify When Run", and tap Next.'),
          const _Step(4, 'Tap "New Blank Automation" and add the action "Get Contents of URL".'),
          _Step(5, 'Set the URL to the address below.', copy: (url, 'Address'), onCopy: _copy),
          const _Step(6, 'Tap the arrow to show more: set Method to POST.'),
          const _Step(
            7,
            'Under Headers, add one: Key "Authorization", Value: paste the key you copied in step 1 '
            '(it starts with "Bearer fin_").',
          ),
          const _Step(
            8,
            'Under Request Body choose JSON and add three Text fields:\n'
            '• text: tap the field, pick Shortcut Input, then tap it and choose Content\n'
            '• sender: Shortcut Input again, but choose Sender\n'
            '• channel: type shortcut',
          ),
          const _Step(9, 'Tap Done. The next bank SMS you get will show up in Transactions with an Auto tag.'),
          const SizedBox(height: 12),
          const Text(
            'Tip: to test it, open the automation and tap the play button, or forward an old bank SMS to yourself.',
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.n, this.text, {this.copy, this.onCopy});

  final int n;
  final String text;
  final (String, String)? copy;
  final void Function(String value, String what)? onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.primarySoft,
            child: Text('$n', style: const TextStyle(fontSize: 12, color: AppColors.primary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text),
                if (copy != null) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => onCopy?.call(copy!.$1, copy!.$2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadii.icon),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(copy!.$1, style: const TextStyle(fontFamily: 'Courier', fontSize: 12)),
                          ),
                          const Icon(Icons.copy, size: 16, color: AppColors.muted),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

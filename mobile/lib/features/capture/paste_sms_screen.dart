import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/remote/capture_api.dart';
import '../../providers.dart';

/// Paste a bank or telebirr SMS; the server reads it and adds the
/// transaction. Also the quickest way to try the parsers on a real message.
class PasteSmsScreen extends ConsumerStatefulWidget {
  const PasteSmsScreen({super.key});

  @override
  ConsumerState<PasteSmsScreen> createState() => _PasteSmsScreenState();
}

class _PasteSmsScreenState extends ConsumerState<PasteSmsScreen> {
  final _text = TextEditingController();
  String? _sender;
  bool _sending = false;
  IngestResult? _result;
  String? _error;

  /// Who the SMS came from helps pick the right bank's format.
  static const _senders = <(String, String)>[
    ('127', 'telebirr (127)'),
    ('CBE', 'CBE'),
    ('CBO', 'Cooperative Bank of Oromia'),
    ('BOA', 'Bank of Abyssinia'),
  ];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      if (mounted) setState(() => _error = 'The clipboard is empty. Copy the SMS in Messages first.');
      return;
    }
    setState(() {
      _text.text = text;
      _error = null;
      _result = null;
    });
  }

  Future<void> _send() async {
    final api = ref.read(captureApiProvider);
    final text = _text.text.trim();
    if (api == null || text.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await api.ingest(text: text, sender: _sender);
      if (!mounted) return;
      setState(() => _result = result);
      // Bring the new transaction down to the phone right away.
      await ref.read(syncSchedulerProvider)?.syncNow();
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't reach the server. Check your connection and try again.");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasBackend = ref.watch(configProvider).hasBackend;
    return Scaffold(
      appBar: AppBar(title: const Text('Paste bank SMS'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const Text(
              'Copy a bank or telebirr message in Messages, then paste it here. '
              'We read the amount, who it was with and the date, and add the transaction.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('paste'),
              onPressed: _sending ? null : _paste,
              icon: const Icon(Icons.content_paste),
              label: const Text('Paste from clipboard'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('sms-text'),
              controller: _text,
              minLines: 5,
              maxLines: 10,
              maxLength: 2000,
              onChanged: (_) => setState(() => _result = null),
              decoration: const InputDecoration(hintText: 'Dear Customer, your account 1****1234 has been debited…'),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<String?>(
              initialValue: _sender,
              decoration: const InputDecoration(labelText: 'From (optional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text("Don't know")),
                for (final (value, label) in _senders) DropdownMenuItem(value: value, child: Text(label)),
              ],
              onChanged: (v) => setState(() => _sender = v),
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('send'),
              onPressed: !hasBackend || _sending || _text.text.trim().isEmpty ? null : _send,
              child: _sending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Add from SMS'),
            ),
            if (!hasBackend)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Reading SMS needs the server, and no backend is configured.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              _ResultCard(icon: Icons.error_outline, color: AppColors.danger, title: _error!),
            ],
            if (_result != null) ...[const SizedBox(height: 16), _resultCard(context, _result!)],
          ],
        ),
      ),
    );
  }

  Widget _resultCard(BuildContext context, IngestResult result) {
    void open(String id) => context.pushReplacement('/transactions/$id');
    return switch (result) {
      IngestCreated(:final transactionId, :final needsReview) => _ResultCard(
        icon: Icons.check_circle_outline,
        color: AppColors.income,
        title: needsReview ? 'Added. It needs a quick look.' : 'Added',
        detail: needsReview ? "We weren't sure about the category. Check it on the transaction." : null,
        action: ('View transaction', () => open(transactionId)),
      ),
      IngestDuplicate(:final transactionId) => _ResultCard(
        icon: Icons.content_copy,
        color: AppColors.muted,
        title: 'Already recorded',
        detail: 'This SMS was added before, so nothing changed.',
        action: transactionId == null ? null : ('View transaction', () => open(transactionId)),
      ),
      IngestEnriched(:final transactionId) => _ResultCard(
        icon: Icons.merge_type,
        color: AppColors.income,
        title: 'Added details to an existing transaction',
        action: ('View transaction', () => open(transactionId)),
      ),
      IngestIgnored(:final reason) => _ResultCard(
        icon: Icons.info_outline,
        color: AppColors.muted,
        title: 'Not added',
        detail: ignoredReason(reason),
      ),
      IngestUnrecognized() => _ResultCard(
        icon: Icons.help_outline,
        color: const Color(0xFFB7791F),
        title: "Couldn't read this message",
        detail: "This bank's format is new to us. You can add the transaction by hand.",
        action: ('Add by hand', () => context.pushReplacement('/add')),
      ),
    };
  }
}

/// Why a message was skipped, in plain words.
String ignoredReason(String reason) => switch (reason) {
  'otp' => "That's a one-time code, not a payment.",
  'credit_line_drawdown' => "That's a loan drawdown, so it isn't counted as income.",
  'bonus' || 'promo' => "That's a promotion, not a payment.",
  'security_notice' => "That's a security notice, not a payment.",
  _ => "That message isn't a transaction.",
};

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.icon, required this.color, required this.title, this.detail, this.action});

  final IconData icon;
  final Color color;
  final String title;
  final String? detail;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('result'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (detail != null) ...[
                    const SizedBox(height: 4),
                    Text(detail!, style: const TextStyle(color: AppColors.muted)),
                  ],
                  if (action != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(onPressed: action!.$2, child: Text(action!.$1)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

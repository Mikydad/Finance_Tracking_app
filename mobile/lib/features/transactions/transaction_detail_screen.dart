import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../domain/transaction.dart';
import '../../providers.dart';
import '../../widgets/category_icon.dart';
import 'delete_with_undo.dart';

class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txn = ref.watch(transactionProvider(id));
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction'), centerTitle: true),
      body: txn.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (t) => t == null ? const Center(child: Text('This transaction was deleted.')) : _Details(t),
      ),
    );
  }
}

class _Details extends ConsumerWidget {
  const _Details(this.t);

  final Txn t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final categories = ref.watch(categoryByIdProvider).value ?? const {};
    final accounts = ref.watch(accountsProvider).value ?? const [];
    final category = categories[t.categoryId];
    final account = accounts.where((a) => a.id == t.accountId).firstOrNull;
    final total = t.signedTotal;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Center(child: CategoryIcon(category, parent: categories[category?.parentId], size: 56)),
        const SizedBox(height: 16),
        Center(
          child: Text(
            '${total >= 0 ? '+' : '-'}${formatBirrCompact(total.abs())} ${t.currency}',
            style: theme.textTheme.headlineMedium?.copyWith(color: total >= 0 ? AppColors.income : null),
          ),
        ),
        Center(child: Text(t.title, style: theme.textTheme.titleMedium)),
        const SizedBox(height: 12),
        if (t.isAutomatic) const Center(child: _Badge('Automatically detected', Icons.check_circle_outline)),
        if (t.status == TransactionStatus.needsReview)
          const Center(child: _Badge('Needs a quick look', Icons.help_outline, warning: true)),
        const SizedBox(height: 20),
        _ReasonField(t),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              _Row('Category', category?.name ?? 'Uncategorized'),
              _Row('Date', longDate(t.occurredAt)),
              _Row('Time', clock(t.occurredAt)),
              if (account != null) _Row('Payment source', account.name),
              if (t.counterpartyAccount != null)
                _Row(t.type == TransactionType.income ? 'From account' : 'To account', t.counterpartyAccount!),
              if (t.fee > 0) _Row('Fee', '${formatBirr(t.fee)} ${t.currency}'),
              if (t.description != null) _Row('Bank says', t.description!),
              if (t.referenceId != null)
                _Row(
                  'Transaction ID',
                  t.referenceId!,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: t.referenceId!));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction ID copied')));
                  },
                ),
            ],
          ),
        ),
        _History(t),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('edit'),
          onPressed: () => context.push('/transactions/${t.id}/edit'),
          child: const Text('Edit transaction'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('delete'),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
          onPressed: () async {
            await deleteWithUndo(context, ref, t.id);
            if (context.mounted) context.pop();
          },
          child: const Text('Delete transaction'),
        ),
      ],
    );
  }
}

/// The reason, edited in place: one tap and type. Saves when the keyboard
/// closes (and while typing, after a pause), so there's no Save button.
/// Filled from the bank receipt when the sender wrote one.
class _ReasonField extends ConsumerStatefulWidget {
  const _ReasonField(this.t);

  final Txn t;

  @override
  ConsumerState<_ReasonField> createState() => _ReasonFieldState();
}

class _ReasonFieldState extends ConsumerState<_ReasonField> {
  late final _controller = TextEditingController(text: widget.t.notes);
  final _focus = FocusNode();
  Timer? _debounce;

  /// Read up front: the last save happens in dispose, when ref can't be used.
  late final TransactionRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(transactionRepositoryProvider);
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(_ReasonField old) {
    super.didUpdateWidget(old);
    // A receipt (or another phone) filled it in while this was on screen.
    if (!_focus.hasFocus && widget.t.notes != old.t.notes) _controller.text = widget.t.notes ?? '';
  }

  void _save() {
    _debounce?.cancel();
    final text = _controller.text.trim();
    if (text == (widget.t.notes ?? '')) return;
    _repo.updateNotes(widget.t.id, text.isEmpty ? null : text);
  }

  void _use(String suggestion) {
    _controller.text = suggestion;
    _save();
    setState(() {});
  }

  @override
  void dispose() {
    _save();
    _debounce?.cancel();
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final related = ref.watch(relatedTransactionsProvider(widget.t.id)).value ?? const [];
    final lastReason = related.map((r) => r.notes).nonNulls.firstOrNull;
    final suggest = lastReason != null && _controller.text.trim().isEmpty && !_focus.hasFocus;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'REASON',
              style: TextStyle(fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: AppColors.muted),
            ),
            TextField(
              key: const Key('reason'),
              controller: _controller,
              focusNode: _focus,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 800), _save);
              },
              decoration: InputDecoration(
                hintText: 'What was it for? Tap to add',
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                suffixIcon: _focus.hasFocus
                    ? IconButton(
                        tooltip: 'Done',
                        icon: const Icon(Icons.check, color: AppColors.primary),
                        onPressed: _focus.unfocus,
                      )
                    : const Icon(Icons.edit_outlined, size: 18, color: AppColors.muted),
              ),
            ),
            if (suggest)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: ActionChip(
                  key: const Key('reason-suggestion'),
                  avatar: const Icon(Icons.history, size: 16),
                  label: Text('Last time: $lastReason', overflow: TextOverflow.ellipsis),
                  onPressed: () => _use(lastReason),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Hana Girma · 6 times · 3,200 ETB sent": everything with the same person
/// or shop, matched by account number or name. Tap for the full list.
class _History extends ConsumerWidget {
  const _History(this.t);

  final Txn t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final related = ref.watch(relatedTransactionsProvider(t.id)).value ?? const [];
    if (related.isEmpty) return const SizedBox.shrink();
    final all = [t, ...related];
    final sent = all.where((x) => x.type != TransactionType.income).fold<int>(0, (s, x) => s + x.amount + x.fee);
    final received = all.where((x) => x.type == TransactionType.income).fold<int>(0, (s, x) => s + x.amount);
    final totals = [
      if (sent > 0) '${formatBirrCompact(sent)} ETB out',
      if (received > 0) '${formatBirrCompact(received)} ETB in',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: ListTile(
          key: const Key('history'),
          leading: const Icon(Icons.history, color: AppColors.primary),
          title: Text('${all.length} times with ${t.counterpartyName ?? t.counterpartyAccount ?? 'them'}'),
          subtitle: Text(totals, style: const TextStyle(color: AppColors.muted)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/transactions/${t.id}/related'),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      title: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
      trailing: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(value, textAlign: TextAlign.end, overflow: TextOverflow.ellipsis),
            ),
            if (onTap != null) ...[const SizedBox(width: 6), const Icon(Icons.copy, size: 16, color: AppColors.muted)],
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.icon, {this.warning = false});

  final String label;
  final IconData icon;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? const Color(0xFFB7791F) : AppColors.income;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: warning ? const Color(0xFFFFF1D6) : AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 13)),
        ],
      ),
    );
  }
}

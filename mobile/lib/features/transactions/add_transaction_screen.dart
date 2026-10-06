import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../domain/account.dart';
import '../../domain/category.dart';
import '../../domain/transaction.dart';
import '../../providers.dart';
import '../../widgets/category_icon.dart';

/// Add a transaction fast: amount first, then (optionally) what it was and a
/// category. Passing [existing] turns it into the edit screen.
class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key, this.existing});

  final Txn? existing;

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  late TransactionType _type = widget.existing?.type ?? TransactionType.expense;
  late final _amount = TextEditingController(
    text: widget.existing == null ? '' : formatBirrCompact(widget.existing!.amount).replaceAll(',', ''),
  );
  late final _what = TextEditingController(text: widget.existing?.counterpartyName);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  final _amountFocus = FocusNode();
  final _scroll = ScrollController();
  late String? _categoryId = widget.existing?.categoryId;
  late String? _accountId = widget.existing?.accountId;
  late DateTime _when = widget.existing?.occurredAt ?? DateTime.now();
  String? _amountError;
  bool _saving = false;

  bool get _editing => widget.existing != null;

  /// The form's starting values, to tell whether anything was changed.
  late final List<Object?> _initial = _snapshot();

  List<Object?> _snapshot() => [_type, _amount.text, _what.text, _notes.text, _categoryId, _accountId, _when];

  bool get _dirty {
    final now = _snapshot();
    for (var i = 0; i < now.length; i++) {
      if (now[i] != _initial[i]) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _initial; // capture before any edits
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_editing ? 'Discard your changes?' : 'Discard this transaction?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
        ],
      ),
    );
    if (discard == true && mounted) context.pop();
  }

  @override
  void dispose() {
    _amount.dispose();
    _what.dispose();
    _notes.dispose();
    _amountFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2015),
      lastDate: _when.isAfter(now) ? _when : now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
    if (!mounted) return;
    setState(() {
      final t = time ?? TimeOfDay.fromDateTime(_when);
      final picked = DateTime(date.year, date.month, date.day, t.hour, t.minute);
      // A later time today would be in the future; use now instead.
      _when = picked.isAfter(now) ? now : picked;
    });
  }

  Future<String?> _resolveAccount() async {
    if (_accountId != null) return _accountId;
    final repo = ref.read(accountRepositoryProvider);
    if (!ref.read(configProvider).hasBackend) return (await repo.ensureLocalCash()).id;
    return (await repo.cash())?.id ?? ref.read(accountsProvider).value?.firstOrNull?.id;
  }

  Future<void> _save() async {
    final amount = parseBirr(_amount.text);
    if (amount == null) {
      setState(() => _amountError = 'Enter an amount, like 250 or 1,250.50');
      // The amount sits at the top; bring it and its error back into view.
      _amountFocus.requestFocus();
      if (_scroll.hasClients) {
        _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
      return;
    }
    setState(() {
      _amountError = null;
      _saving = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final accountId = await _resolveAccount();
      if (accountId == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Your accounts are still syncing. Try again in a moment.')),
        );
        return;
      }
      final what = _what.text.trim().isEmpty ? null : _what.text.trim();
      final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
      final repo = ref.read(transactionRepositoryProvider);
      if (_editing) {
        await repo.update(
          widget.existing!.copyWith(
            accountId: accountId,
            type: _type,
            amount: amount,
            occurredAt: _when,
            counterpartyName: () => what,
            categoryId: () => _categoryId,
            notes: () => notes,
          ),
        );
      } else {
        await repo.add(
          accountId: accountId,
          type: _type,
          amount: amount,
          occurredAt: _when,
          counterpartyName: what,
          categoryId: _categoryId,
          notes: notes,
        );
      }
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = (ref.watch(categoriesProvider).value ?? const <Category>[])
        .where((c) => c.isTopLevel && c.fits(_type.name))
        .toList();
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('close'),
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(_editing ? 'Edit transaction' : 'Add transaction'),
          actions: [
            if (!_editing && ref.watch(configProvider).hasBackend)
              IconButton(
                key: const Key('from-sms'),
                tooltip: 'Paste bank SMS',
                icon: const Icon(Icons.sms_outlined),
                onPressed: () => context.push('/paste'),
              ),
          ],
          centerTitle: true,
        ),
        body: SafeArea(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              SegmentedButton<TransactionType>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: TransactionType.expense, label: Text('Expense')),
                  ButtonSegment(value: TransactionType.income, label: Text('Income')),
                  ButtonSegment(value: TransactionType.transfer, label: Text('Transfer')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.single),
              ),
              const SizedBox(height: 24),
              Text('How much?', style: theme.textTheme.titleSmall?.copyWith(color: AppColors.muted)),
              TextField(
                key: const Key('amount'),
                controller: _amount,
                onChanged: (_) => setState(() {}),
                focusNode: _amountFocus,
                autofocus: !_editing,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: '0',
                  suffixText: 'ETB',
                  errorText: _amountError,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
              const SizedBox(height: 16),
              Text('What was it?', style: theme.textTheme.titleSmall?.copyWith(color: AppColors.muted)),
              const SizedBox(height: 8),
              TextField(
                key: const Key('what'),
                controller: _what,
                onChanged: (_) => setState(() {}),
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'e.g. ABC Store, Lunch, Abebe'),
              ),
              const SizedBox(height: 24),
              Text('Category', style: theme.textTheme.titleSmall?.copyWith(color: AppColors.muted)),
              const SizedBox(height: 12),
              if (categories.isEmpty)
                const Text('Categories appear after the first sync.', style: TextStyle(color: AppColors.muted))
              else
                _CategoryGrid(
                  categories: categories,
                  selectedId: _categoryId,
                  onSelected: (id) => setState(() => _categoryId = _categoryId == id ? null : id),
                ),
              const SizedBox(height: 24),
              Text('Date', style: theme.textTheme.titleSmall?.copyWith(color: AppColors.muted)),
              const SizedBox(height: 8),
              _FieldButton(
                icon: Icons.calendar_today_outlined,
                label: '${dayLabel(_when)} · ${clock(_when)}',
                onTap: _pickDateTime,
              ),
              if (accounts.length > 1) ...[
                const SizedBox(height: 16),
                Text('Paid from', style: theme.textTheme.titleSmall?.copyWith(color: AppColors.muted)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _accountId ?? accounts.where((a) => a.isCash).firstOrNull?.id,
                  items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
                  onChanged: (id) => setState(() => _accountId = id),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _notes,
                onChanged: (_) => setState(() {}),
                maxLines: 2,
                decoration: const InputDecoration(hintText: 'Add a note (optional)'),
              ),
              const SizedBox(height: 28),
              FilledButton(
                key: const Key('save'),
                onPressed: _saving ? null : _save,
                child: Text(_editing ? 'Save changes' : 'Add transaction'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.categories, required this.selectedId, required this.onSelected});

  final List<Category> categories;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.9,
      children: [
        for (final c in categories)
          _CategoryCell(category: c, selected: c.id == selectedId, onTap: () => onSelected(c.id)),
      ],
    );
  }
}

class _CategoryCell extends StatelessWidget {
  const _CategoryCell({required this.category, required this.selected, required this.onTap});

  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: Key('category-${category.key ?? category.id}'),
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: selected ? AppColors.primary : AppColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CategoryIcon(category, size: 32),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                // Shrinks long names like "Entertainment" instead of cutting them off.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    category.name,
                    maxLines: 1,
                    style: TextStyle(fontSize: 12, color: selected ? Colors.white : AppColors.text),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldButton extends StatelessWidget {
  const _FieldButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.button),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.button),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.muted),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/periods.dart';
import '../../core/theme.dart';
import '../../domain/category.dart';
import '../../domain/goal.dart';
import '../../providers.dart';
import '../coach/coach_card.dart';
import 'goal_progress.dart';

/// Your goals and how each is going this week or month.
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(goalProgressProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Goals'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          ...switch (progress) {
            AsyncData(:final value) when value.isEmpty => [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'Set a limit on spending, or a target for what you earn or save, '
                  'and see every day whether you are on track.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            ],
            AsyncData(:final value) => [
              for (final p in value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GoalCard(
                    progress: p,
                    onTap: () => showGoalEditor(context, ref, existing: p.goal),
                  ),
                ),
            ],
            _ => [const Center(child: CircularProgressIndicator())],
          },
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            key: const Key('add-goal'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.add),
            label: const Text('Add a goal'),
            onPressed: () => showGoalEditor(context, ref),
          ),
          const SizedBox(height: 16),
          const CoachCard(),
        ],
      ),
    );
  }
}

/// One goal: what it is, a progress bar, and on track / slow down / over.
class GoalCard extends ConsumerWidget {
  const GoalCard({super.key, required this.progress, this.onTap, this.compact = false});

  final GoalProgress progress;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoryByIdProvider).value ?? const {};
    final color = switch (progress.status) {
      GoalStatus.onTrack || GoalStatus.reached => AppColors.income,
      GoalStatus.atRisk => const Color(0xFFB7791F),
      GoalStatus.missed => AppColors.danger,
    };
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      progress.title(categories[progress.goal.categoryId]?.name),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadii.chip),
                    ),
                    child: Text(progress.statusLabel, style: TextStyle(color: color, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.fraction.clamp(0, 1).toDouble(),
                  minHeight: 8,
                  backgroundColor: AppColors.border,
                  color: color,
                ),
              ),
              const SizedBox(height: 6),
              Text(progress.detail, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Create a goal, or change or delete [existing].
Future<void> showGoalEditor(BuildContext context, WidgetRef ref, {Goal? existing}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _GoalEditor(existing: existing),
);

class _GoalEditor extends ConsumerStatefulWidget {
  const _GoalEditor({this.existing});

  final Goal? existing;

  @override
  ConsumerState<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends ConsumerState<_GoalEditor> {
  late GoalKind _kind = widget.existing?.kind ?? GoalKind.spendMax;
  late PeriodKind _period = widget.existing?.period ?? PeriodKind.week;
  late String? _categoryId = widget.existing?.categoryId;
  late final _amount = TextEditingController(
    text: widget.existing == null ? '' : formatBirrCompact(widget.existing!.amount).replaceAll(',', ''),
  );
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseBirr(_amount.text);
    if (amount == null) {
      setState(() => _error = 'Enter an amount, like 5000');
      return;
    }
    await ref
        .read(goalRepositoryProvider)
        .save(
          id: widget.existing?.id,
          kind: _kind,
          period: _period,
          amount: amount,
          categoryId: _kind == GoalKind.spendMax ? _categoryId : null,
        );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    await ref.read(goalRepositoryProvider).delete(widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final categories = (ref.watch(categoriesProvider).value ?? const <Category>[])
        .where((c) => c.isTopLevel && c.fits('expense'))
        .toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.existing == null ? 'New goal' : 'Edit goal', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          SegmentedButton<GoalKind>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: GoalKind.spendMax, label: Text('Spend at most')),
              ButtonSegment(value: GoalKind.earnMin, label: Text('Earn')),
              ButtonSegment(value: GoalKind.saveMin, label: Text('Save')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.single),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('goal-amount'),
            controller: _amount,
            autofocus: widget.existing == null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            style: Theme.of(context).textTheme.headlineSmall,
            decoration: InputDecoration(hintText: '5000', suffixText: 'ETB', errorText: _error),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 16),
          SegmentedButton<PeriodKind>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: PeriodKind.week, label: Text('Every week')),
              ButtonSegment(value: PeriodKind.month, label: Text('Every month')),
            ],
            selected: {_period},
            onSelectionChanged: (s) => setState(() => _period = s.single),
          ),
          if (_kind == GoalKind.spendMax) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              key: const Key('goal-category'),
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'On'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All spending')),
                for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (id) => setState(() => _categoryId = id),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(key: const Key('save-goal'), onPressed: _save, child: const Text('Save goal')),
          if (widget.existing != null)
            TextButton(
              key: const Key('delete-goal'),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: _delete,
              child: const Text('Delete goal'),
            ),
        ],
      ),
    );
  }
}

/// Home's goals section: compact cards, or a nudge to set the first one.
class HomeGoals extends ConsumerWidget {
  const HomeGoals({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(goalProgressProvider).value ?? const <GoalProgress>[];
    if (list.isEmpty) {
      return Card(
        child: ListTile(
          key: const Key('home-set-goal'),
          leading: const Icon(Icons.flag_outlined, color: AppColors.primary),
          title: const Text('Set a goal'),
          subtitle: const Text('e.g. spend at most 5,000 ETB a week'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/goals'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Goals', style: Theme.of(context).textTheme.titleMedium)),
            TextButton(onPressed: () => context.push('/goals'), child: const Text('All')),
          ],
        ),
        for (final p in list.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: GoalCard(progress: p, compact: true, onTap: () => context.push('/goals')),
          ),
      ],
    );
  }
}

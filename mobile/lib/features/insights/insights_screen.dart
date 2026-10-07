import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/periods.dart';
import '../../core/theme.dart';
import '../../domain/category.dart';
import '../../domain/transaction.dart';
import '../../providers.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/txn_tile.dart';
import 'period_stats.dart';

/// Day / Week / Month analytics: totals against the period before, a daily
/// chart, categories, people and shops, and the biggest expenses. Computed on
/// the phone from the local database, so it works offline.
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  PeriodKind _kind = PeriodKind.week;

  /// How many periods back from the current one (0 = this one).
  int _offset = 0;

  @override
  Widget build(BuildContext context) {
    final periods = ref.watch(periodsProvider);
    final now = DateTime.now();
    final period = periods.shift(periods.containing(_kind, now), -_offset);
    final previous = periods.shift(period, -1);
    final categories = ref.watch(categoryByIdProvider).value ?? const {};
    final current = ref.watch(periodTransactionsProvider(period));
    final before = ref.watch(periodTransactionsProvider(previous)).value ?? const [];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('Insights', style: theme.textTheme.headlineSmall)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          SegmentedButton<PeriodKind>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: PeriodKind.day, label: Text('Day')),
              ButtonSegment(value: PeriodKind.week, label: Text('Week')),
              ButtonSegment(value: PeriodKind.month, label: Text('Month')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() {
              _kind = s.single;
              _offset = 0;
            }),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                key: const Key('period-back'),
                tooltip: 'Earlier',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() => _offset++),
              ),
              Expanded(
                child: Text(
                  periods.label(period, now: now),
                  key: const Key('period-label'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                key: const Key('period-forward'),
                tooltip: 'Later',
                icon: const Icon(Icons.chevron_right),
                onPressed: _offset == 0 ? null : () => setState(() => _offset--),
              ),
            ],
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: current.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('Could not load: $e'),
              data: (list) => _Body(
                key: ValueKey(period),
                stats: PeriodStats.of(list, period, periods, categories),
                before: PeriodStats.of(before, previous, periods, categories),
                previousLabel: _previousName(_kind),
                periods: periods,
                categories: categories,
                transactions: list,
                now: now,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _previousName(PeriodKind kind) => switch (kind) {
    PeriodKind.day => 'the day before',
    PeriodKind.week => 'the week before',
    PeriodKind.month => 'the month before',
  };
}

class _Body extends StatelessWidget {
  const _Body({
    super.key,
    required this.stats,
    required this.before,
    required this.previousLabel,
    required this.periods,
    required this.categories,
    required this.transactions,
    required this.now,
  });

  final PeriodStats stats;
  final PeriodStats before;
  final String previousLabel;
  final Periods periods;
  final Map<String, Category> categories;
  final List<Txn> transactions;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final period = stats.period;
    if (stats.count == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text('No transactions in this period.', style: TextStyle(color: AppColors.muted)),
        ),
      );
    }
    final projected = stats.projectedSpent(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Totals(stats: stats, before: before, previousLabel: previousLabel),
        if (period.kind != PeriodKind.day) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              child: _Chart(stats: stats, periods: periods),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              [
                'Daily average ${formatBirrCompact(stats.dailyAverage(now))} ETB',
                if (projected != null && projected > stats.spent)
                  'on pace for ${formatBirrCompact(projected)} ETB by the end',
              ].join(' · '),
              key: const Key('pace'),
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
            ),
          ),
        ],
        if (stats.byCategory.isNotEmpty) ...[
          const _Heading('Where it went'),
          Card(
            child: Column(
              children: [
                for (final row in stats.byCategory)
                  _CategoryRow(
                    category: categories[row.categoryId],
                    amount: row.amount,
                    total: stats.spent,
                    onTap: () => context.push('/insights/category/${row.categoryId ?? 'none'}', extra: period),
                  ),
              ],
            ),
          ),
        ],
        if (stats.topCounterparties.isNotEmpty) ...[
          const _Heading('Top people and shops'),
          Card(
            child: Column(
              children: [
                for (final p in stats.topCounterparties)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_outline, color: AppColors.muted),
                    title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${p.count} ${p.count == 1 ? 'payment' : 'payments'}'),
                    trailing: Text('${formatBirrCompact(p.amount)} ETB'),
                  ),
              ],
            ),
          ),
        ],
        _Heading(period.kind == PeriodKind.day ? 'Transactions' : 'Biggest expenses'),
        Card(
          child: Column(
            children: [
              for (final t in period.kind == PeriodKind.day ? transactions : stats.biggest)
                TxnTile(txn: t, categories: categories, onTap: () => context.push('/transactions/${t.id}')),
            ],
          ),
        ),
      ],
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.stats, required this.before, required this.previousLabel});

  final PeriodStats stats;
  final PeriodStats before;
  final String previousLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = percentChange(stats.spent, before.spent);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppRadii.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Spent', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.primary)),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: formatBirrCompact(stats.spent), style: theme.textTheme.headlineMedium),
                TextSpan(text: ' ETB', style: theme.textTheme.titleMedium),
              ],
            ),
            key: const Key('insights-spent'),
          ),
          if (change != null)
            Text(
              '${change >= 0 ? '↑' : '↓'} ${change.abs()}% vs $previousLabel',
              style: theme.textTheme.bodySmall?.copyWith(color: change > 0 ? AppColors.danger : AppColors.income),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _Figure('Income', stats.income, color: AppColors.income)),
              Expanded(
                child: _Figure(
                  'Net',
                  stats.net,
                  color: stats.net >= 0 ? AppColors.income : AppColors.danger,
                  signed: true,
                ),
              ),
              Expanded(child: _Figure('Fees', stats.fees)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.santim, {this.color, this.signed = false});

  final String label;
  final int santim;
  final Color? color;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final sign = signed && santim > 0 ? '+' : (santim < 0 ? '-' : '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        Text(
          '$sign${formatBirrCompact(santim.abs())}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Spending (or income) per day, as simple bars.
class _Chart extends StatefulWidget {
  const _Chart({required this.stats, required this.periods});

  final PeriodStats stats;
  final Periods periods;

  @override
  State<_Chart> createState() => _ChartState();
}

class _ChartState extends State<_Chart> {
  bool _income = false;

  @override
  Widget build(BuildContext context) {
    final buckets = widget.stats.buckets;
    final values = [for (final b in buckets) _income ? b.income : b.spent];
    final max = values.fold<int>(0, (m, v) => v > m ? v : m);
    final kind = widget.stats.period.kind;
    final color = _income ? AppColors.income : AppColors.primary;
    final labelEvery = buckets.length > 7 ? 5 : 1;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (final (label, income) in [('Spent', false), ('Income', true)])
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ChoiceChip(
                  key: Key('chart-$label'),
                  label: Text(label),
                  selected: _income == income,
                  labelStyle: TextStyle(color: _income == income ? Colors.white : AppColors.text, fontSize: 12),
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _income = income),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 140,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < buckets.length; i++)
                Expanded(
                  child: Tooltip(
                    message: '${formatBirrCompact(values[i])} ETB',
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: buckets.length > 7 ? 1 : 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 260),
                            height: max == 0 ? 2 : 2 + 110 * values[i] / max,
                            decoration: BoxDecoration(
                              color: values[i] == 0 ? AppColors.border : color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 14,
                            child: i % labelEvery == 0
                                ? Text(
                                    widget.periods.bucketLabel(buckets[i].period, kind),
                                    style: const TextStyle(fontSize: 10, color: AppColors.muted),
                                    overflow: TextOverflow.visible,
                                    softWrap: false,
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.amount, required this.total, required this.onTap});

  final Category? category;
  final int amount;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final share = total == 0 ? 0.0 : amount / total;
    return ListTile(
      onTap: onTap,
      leading: CategoryIcon(category, size: 36),
      title: Row(
        children: [
          Expanded(child: Text(category?.name ?? 'Uncategorized', maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text('${formatBirrCompact(amount)} ETB'),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: share,
                  minHeight: 6,
                  backgroundColor: AppColors.border,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('${(share * 100).round()}%', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

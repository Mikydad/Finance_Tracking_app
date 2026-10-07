import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers.dart';
import 'coach.dart';

/// "How am I doing?": the AI coach's read on your goals and spending, with a
/// few concrete suggestions. Shows the last answer instantly (also offline)
/// and refreshes on tap.
class CoachCard extends ConsumerWidget {
  const CoachCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(configProvider).hasBackend) return const SizedBox.shrink();
    final state = ref.watch(coachProvider);
    final advice = state.advice;
    final theme = Theme.of(context);

    return Card(
      color: AppColors.primarySoft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    advice == null ? 'How am I doing?' : 'Coach',
                    style: theme.textTheme.titleSmall?.copyWith(color: AppColors.primary),
                  ),
                ),
                if (state.loading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  IconButton(
                    key: const Key('coach-refresh'),
                    tooltip: advice == null ? 'Ask the coach' : 'Refresh',
                    icon: Icon(advice == null ? Icons.arrow_forward : Icons.refresh, color: AppColors.primary),
                    onPressed: () => ref.read(coachProvider.notifier).refresh(),
                  ),
              ],
            ),
            if (advice == null && !state.loading)
              const Padding(
                padding: EdgeInsets.only(right: 8, bottom: 4),
                child: Text(
                  'Tap the arrow for a read on your goals and spending, with what to do next.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            if (advice != null) ...[
              Text(advice.headline, key: const Key('coach-headline'), style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Padding(padding: const EdgeInsets.only(right: 8), child: Text(advice.assessment)),
              for (final g in advice.goalNotes)
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 8),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${g.goal}: ',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: g.note),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              for (final s in advice.suggestions)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.check_circle_outline, size: 16, color: AppColors.primary),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${s.title}. ',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              TextSpan(text: s.detail),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (state.failed)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  "Couldn't reach the coach. Check your connection and try again.",
                  key: Key('coach-failed'),
                  style: TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              )
            else if (state.updatedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Updated ${_ago(state.updatedAt!)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} ${d.inDays == 1 ? 'day' : 'days'} ago';
  }
}

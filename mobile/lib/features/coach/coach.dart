import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/periods.dart';
import '../../data/local/models.dart';
import '../../providers.dart';
import '../goals/goal_progress.dart';
import 'coach_summary.dart';

class CoachAdvice {
  const CoachAdvice({
    required this.headline,
    required this.assessment,
    this.suggestions = const [],
    this.goalNotes = const [],
  });

  factory CoachAdvice.fromJson(Map<String, dynamic> j) => CoachAdvice(
    headline: j['headline'] as String,
    assessment: j['assessment'] as String,
    suggestions: [
      for (final s in (j['suggestions'] as List? ?? const []).cast<Map<String, dynamic>>())
        (title: s['title'] as String, detail: s['detail'] as String),
    ],
    goalNotes: [
      for (final g in (j['goalNotes'] as List? ?? const []).cast<Map<String, dynamic>>())
        (goal: g['goal'] as String, note: g['note'] as String),
    ],
  );

  final String headline;
  final String assessment;
  final List<({String title, String detail})> suggestions;
  final List<({String goal, String note})> goalNotes;

  Map<String, Object?> toJson() => {
    'headline': headline,
    'assessment': assessment,
    'suggestions': [
      for (final s in suggestions) {'title': s.title, 'detail': s.detail},
    ],
    'goalNotes': [
      for (final g in goalNotes) {'goal': g.goal, 'note': g.note},
    ],
  };
}

/// Talks to the `coach` Edge Function.
abstract class CoachApi {
  Future<CoachAdvice> ask(Map<String, Object?> summary);
}

class SupabaseCoachApi implements CoachApi {
  SupabaseCoachApi(this._client);
  final SupabaseClient _client;

  @override
  Future<CoachAdvice> ask(Map<String, Object?> summary) async {
    final res = await _client.functions.invoke('coach', body: summary);
    return CoachAdvice.fromJson((res.data as Map).cast<String, dynamic>());
  }
}

/// The card's state: the last advice (possibly from an earlier session),
/// whether a refresh is running, and whether the last refresh failed.
class CoachState {
  const CoachState({this.advice, this.updatedAt, this.loading = false, this.failed = false});

  final CoachAdvice? advice;
  final DateTime? updatedAt;
  final bool loading;
  final bool failed;
}

final coachApiProvider = Provider<CoachApi?>(
  (ref) => ref.watch(configProvider).hasBackend ? SupabaseCoachApi(Supabase.instance.client) : null,
);

final coachProvider = NotifierProvider<CoachController, CoachState>(CoachController.new);

/// Optimistic-then-honest: the saved advice shows at once; a refresh needs the
/// network, and if it fails the old advice stays with a quiet note.
class CoachController extends Notifier<CoachState> {
  Isar get _isar => ref.read(isarProvider);

  @override
  CoachState build() {
    _loadSaved();
    return const CoachState();
  }

  Future<void> _loadSaved() async {
    final row = await _isar.localCoachNotes.get(0);
    if (row == null || state.advice != null) return;
    state = CoachState(
      advice: CoachAdvice.fromJson(jsonDecode(row.adviceJson) as Map<String, dynamic>),
      updatedAt: row.createdAt,
    );
  }

  /// Reads straight from the repositories (not from screen providers, which
  /// Riverpod may have paused when no screen is watching them).
  Future<Map<String, Object?>> _summary(DateTime now) async {
    final periods = Periods(await ref.read(prefsRepositoryProvider).watch().first);
    final from = periods.shift(periods.containing(PeriodKind.month, now), -1).start;
    final weekBefore = periods.shift(periods.containing(PeriodKind.week, now), -1).start;
    final txns = await ref
        .read(transactionRepositoryProvider)
        .watch(from: from.isBefore(weekBefore) ? from : weekBefore)
        .first;
    final categories = {
      for (final c in await ref.read(categoryRepositoryProvider).watchAll(includeArchived: true).first) c.id: c,
    };
    final goals = await ref.read(goalRepositoryProvider).watchActive().first;
    return buildCoachSummary(
      txns: txns,
      periods: periods,
      categories: categories,
      goals: [for (final g in goals) GoalProgress.of(g, txns, periods, categories, now)],
      now: now,
    );
  }

  Future<void> refresh() async {
    final api = ref.read(coachApiProvider);
    if (api == null || state.loading) return;
    state = CoachState(advice: state.advice, updatedAt: state.updatedAt, loading: true);
    try {
      final summary = await _summary(DateTime.now());
      final advice = await api.ask(summary);
      final now = DateTime.now();
      await _isar.writeTxn(
        () => _isar.localCoachNotes.put(
          LocalCoachNote()
            ..adviceJson = jsonEncode(advice.toJson())
            ..createdAt = now,
        ),
      );
      state = CoachState(advice: advice, updatedAt: now);
    } catch (_) {
      state = CoachState(advice: state.advice, updatedAt: state.updatedAt, failed: true);
    }
  }
}

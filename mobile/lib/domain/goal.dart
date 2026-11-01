import '../core/periods.dart';

/// spend at most / earn at least / save at least (income − spending).
enum GoalKind { spendMax, earnMin, saveMin }

class Goal {
  const Goal({required this.id, required this.kind, required this.period, required this.amount, this.categoryId});

  final String id;
  final GoalKind kind;

  /// week or month (never day).
  final PeriodKind period;

  /// Santim.
  final int amount;

  /// Spending goals only.
  final String? categoryId;

  static const wireKinds = {GoalKind.spendMax: 'spend_max', GoalKind.earnMin: 'earn_min', GoalKind.saveMin: 'save_min'};

  static GoalKind kindFromWire(String s) => wireKinds.entries.firstWhere((e) => e.value == s).key;
}

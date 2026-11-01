import 'dart:convert';

import 'package:isar_community/isar.dart';
import 'package:uuid/uuid.dart';

import '../../core/periods.dart';
import '../../domain/goal.dart';
import '../local/models.dart';

/// Finance goals: saved on the phone first, then synced (finance_goals).
class GoalRepository {
  GoalRepository(this._isar, {Uuid? uuid, DateTime Function()? clock, String? Function()? userId})
    : _uuid = uuid ?? const Uuid(),
      _now = clock ?? DateTime.now,
      _userId = userId ?? (() => null);

  final Isar _isar;
  final Uuid _uuid;
  final DateTime Function() _now;
  final String? Function() _userId;

  /// Active goals, weekly ones first.
  Stream<List<Goal>> watchActive() => _isar.localGoals
      .filter()
      .deletedAtIsNull()
      .isActiveEqualTo(true)
      .watch(fireImmediately: true)
      .map((rows) => [for (final r in rows) _toDomain(r)]..sort((a, b) => a.period.index.compareTo(b.period.index)));

  /// Creates a goal ([id] null) or replaces an existing one.
  Future<Goal> save({
    String? id,
    required GoalKind kind,
    required PeriodKind period,
    required int amount,
    String? categoryId,
  }) async {
    if (amount <= 0) throw ArgumentError.value(amount, 'amount', 'must be positive santim');
    if (period == PeriodKind.day) throw ArgumentError.value(period, 'period', 'goals are weekly or monthly');
    final now = _now();
    final row = (id == null ? null : await _isar.localGoals.getByUuid(id)) ?? (LocalGoal()..uuid = id ?? _uuid.v7());
    row
      ..kind = Goal.wireKinds[kind]!
      ..period = period.name
      ..amount = amount
      ..categoryId = kind == GoalKind.spendMax ? categoryId : null
      ..isActive = true
      ..deletedAt = null
      ..updatedAt = now;
    final userId = _userId();
    await _isar.writeTxn(() async {
      await _isar.localGoals.put(row);
      await _isar.outboxOps.put(
        OutboxOp()
          ..table = 'finance_goals'
          ..op = 'upsert'
          ..rowId = row.uuid
          ..payload = jsonEncode({
            'id': row.uuid,
            'user_id': ?userId,
            'kind': row.kind,
            'period': row.period,
            'amount': row.amount,
            'category_id': row.categoryId,
            'is_active': true,
            'deleted_at': null,
          })
          ..createdAt = now,
      );
    });
    return _toDomain(row);
  }

  Future<void> delete(String id) async {
    final now = _now();
    await _isar.writeTxn(() async {
      final row = await _isar.localGoals.getByUuid(id);
      if (row == null || row.deletedAt != null) return;
      row
        ..deletedAt = now
        ..updatedAt = now;
      await _isar.localGoals.put(row);
      await _isar.outboxOps.put(
        OutboxOp()
          ..table = 'finance_goals'
          ..op = 'delete'
          ..rowId = id
          ..payload = jsonEncode({'id': id})
          ..createdAt = now,
      );
    });
  }

  static Goal _toDomain(LocalGoal r) => Goal(
    id: r.uuid,
    kind: Goal.kindFromWire(r.kind),
    period: r.period == 'week' ? PeriodKind.week : PeriodKind.month,
    amount: r.amount,
    categoryId: r.categoryId,
  );
}

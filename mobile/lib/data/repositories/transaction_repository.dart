import 'dart:convert';

import 'package:isar_community/isar.dart';
import 'package:uuid/uuid.dart';

import '../../domain/transaction.dart';
import '../local/models.dart';

/// All transaction reads and writes go through here, so features never touch
/// Isar directly and the local database could be swapped later.
abstract class TransactionRepository {
  Stream<List<Txn>> watchRecent({int limit = 50});

  /// Saves locally and queues the change for the next sync push.
  Future<Txn> add({
    required String accountId,
    required TransactionType type,
    required int amount,
    DateTime? occurredAt,
    String? counterpartyName,
    String? categoryId,
    String? notes,
  });

  Future<void> delete(String id);
}

class IsarTransactionRepository implements TransactionRepository {
  IsarTransactionRepository(this._isar, {Uuid? uuid, DateTime Function()? clock})
      : _uuid = uuid ?? const Uuid(),
        _now = clock ?? DateTime.now;

  final Isar _isar;
  final Uuid _uuid;
  final DateTime Function() _now;

  @override
  Stream<List<Txn>> watchRecent({int limit = 50}) {
    return _isar.localTransactions
        .filter()
        .deletedAtIsNull()
        .sortByOccurredAtDesc()
        .limit(limit)
        .watch(fireImmediately: true)
        .map((rows) => rows.map(_toDomain).toList());
  }

  @override
  Future<Txn> add({
    required String accountId,
    required TransactionType type,
    required int amount,
    DateTime? occurredAt,
    String? counterpartyName,
    String? categoryId,
    String? notes,
  }) async {
    if (amount <= 0) throw ArgumentError.value(amount, 'amount', 'must be positive santim');
    final now = _now();
    final row = LocalTransaction()
      ..uuid = _uuid.v7()
      ..accountId = accountId
      ..type = type.name
      ..amount = amount
      ..occurredAt = occurredAt ?? now
      ..counterpartyName = counterpartyName
      ..counterpartyKind = counterpartyName == null ? null : 'unknown'
      ..categoryId = categoryId
      ..categorySource = categoryId == null ? null : 'user'
      ..notes = notes
      ..updatedAt = now;

    await _isar.writeTxn(() async {
      await _isar.localTransactions.put(row);
      await _isar.outboxOps.put(_outbox('upsert', row.uuid, _toServer(row), now));
    });
    return _toDomain(row);
  }

  @override
  Future<void> delete(String id) async {
    final now = _now();
    await _isar.writeTxn(() async {
      final row = await _isar.localTransactions.where().uuidEqualTo(id).findFirst();
      if (row == null || row.deletedAt != null) return;
      row
        ..deletedAt = now
        ..updatedAt = now;
      await _isar.localTransactions.put(row);
      await _isar.outboxOps.put(_outbox('delete', id, {'id': id}, now));
    });
  }

  OutboxOp _outbox(String op, String rowId, Map<String, Object?> payload, DateTime now) => OutboxOp()
    ..table = 'transactions'
    ..op = op
    ..rowId = rowId
    ..payload = jsonEncode(payload)
    ..createdAt = now;

  /// The columns sync_push accepts for transactions, in the server's names.
  static Map<String, Object?> _toServer(LocalTransaction t) => {
        'id': t.uuid,
        'account_id': t.accountId,
        'type': t.type,
        'amount': t.amount,
        'fee': t.fee,
        'currency': t.currency,
        'occurred_at': t.occurredAt.toUtc().toIso8601String(),
        'counterparty_name': t.counterpartyName,
        'counterparty_kind': t.counterpartyKind,
        'category_id': t.categoryId,
        'category_source': t.categorySource,
        'notes': t.notes,
        'status': t.status,
      };

  static Txn _toDomain(LocalTransaction t) => Txn(
        id: t.uuid,
        accountId: t.accountId,
        type: TransactionType.values.byName(t.type),
        amount: t.amount,
        fee: t.fee,
        currency: t.currency,
        occurredAt: t.occurredAt,
        counterpartyName: t.counterpartyName,
        categoryId: t.categoryId,
        notes: t.notes,
        status: switch (t.status) {
          'pending' => TransactionStatus.pending,
          'needs_review' => TransactionStatus.needsReview,
          _ => TransactionStatus.confirmed,
        },
      );
}

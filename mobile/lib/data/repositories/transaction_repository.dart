import 'dart:convert';

import 'package:isar_community/isar.dart';
import 'package:uuid/uuid.dart';

import '../../domain/transaction.dart';
import '../local/models.dart';

/// All transaction reads and writes go through here, so features never touch
/// Isar directly and the local database could be swapped later.
abstract class TransactionRepository {
  /// Live transactions, newest first, optionally of one type and/or in a
  /// date range (`from` inclusive, `to` exclusive).
  Stream<List<Txn>> watch({TransactionType? type, DateTime? from, DateTime? to, int? limit});

  Stream<List<Txn>> watchRecent({int limit = 50}) => watch(limit: limit);

  /// One transaction, or null once it is deleted.
  Stream<Txn?> watchOne(String id);

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

  /// Saves the edited fields of an existing transaction. Picking a category
  /// marks it as chosen by the user, so automatic categorizing won't change it.
  Future<void> update(Txn edited);

  /// Soft delete; [restore] undoes it.
  Future<void> delete(String id);
  Future<void> restore(String id);
}

class IsarTransactionRepository extends TransactionRepository {
  IsarTransactionRepository(this._isar, {Uuid? uuid, DateTime Function()? clock})
    : _uuid = uuid ?? const Uuid(),
      _now = clock ?? DateTime.now;

  final Isar _isar;
  final Uuid _uuid;
  final DateTime Function() _now;

  static const _automaticSources = {'sms', 'shortcut', 'bank'};

  @override
  Stream<List<Txn>> watch({TransactionType? type, DateTime? from, DateTime? to, int? limit}) {
    final query = _isar.localTransactions
        .filter()
        .deletedAtIsNull()
        .optional(type != null, (q) => q.typeEqualTo(type!.name))
        .optional(from != null, (q) => q.occurredAtGreaterThan(from!, include: true))
        .optional(to != null, (q) => q.occurredAtLessThan(to!))
        .sortByOccurredAtDesc();
    final rows = limit == null ? query.watch(fireImmediately: true) : query.limit(limit).watch(fireImmediately: true);
    return rows.asyncMap((list) async {
      final automatic = await _automaticSourceIds();
      return [for (final t in list) _toDomain(t, automatic)];
    });
  }

  @override
  Stream<Txn?> watchOne(String id) {
    return _isar.localTransactions.where().uuidEqualTo(id).watch(fireImmediately: true).asyncMap((rows) async {
      final row = rows.isEmpty ? null : rows.first;
      if (row == null || row.deletedAt != null) return null;
      return _toDomain(row, await _automaticSourceIds());
    });
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
    return _toDomain(row, const {});
  }

  @override
  Future<void> update(Txn edited) async {
    if (edited.amount <= 0) throw ArgumentError.value(edited.amount, 'amount', 'must be positive santim');
    final now = _now();
    await _isar.writeTxn(() async {
      final row = await _isar.localTransactions.where().uuidEqualTo(edited.id).findFirst();
      if (row == null || row.deletedAt != null) return;

      final changes = <String, Object?>{};
      void set<T>(String column, T current, T next, void Function() apply, [Object? wire]) {
        if (current == next) return;
        apply();
        changes[column] = wire ?? next;
      }

      set('account_id', row.accountId, edited.accountId, () => row.accountId = edited.accountId);
      set('type', row.type, edited.type.name, () => row.type = edited.type.name);
      set('amount', row.amount, edited.amount, () => row.amount = edited.amount);
      set(
        'occurred_at',
        row.occurredAt.toUtc(),
        edited.occurredAt.toUtc(),
        () => row.occurredAt = edited.occurredAt,
        edited.occurredAt.toUtc().toIso8601String(),
      );
      set(
        'counterparty_name',
        row.counterpartyName,
        edited.counterpartyName,
        () => row.counterpartyName = edited.counterpartyName,
      );
      set('notes', row.notes, edited.notes, () => row.notes = edited.notes);
      if (row.categoryId != edited.categoryId) {
        row
          ..categoryId = edited.categoryId
          ..categorySource = 'user';
        changes['category_id'] = edited.categoryId;
        changes['category_source'] = 'user';
      }
      if (changes.isEmpty) return;

      // An edit is the user looking at it, so it no longer needs review.
      if (row.status == 'needs_review') {
        row
          ..status = 'confirmed'
          ..reviewReason = null;
        changes['status'] = 'confirmed';
        changes['review_reason'] = null;
      }
      row.updatedAt = now;
      await _isar.localTransactions.put(row);
      await _isar.outboxOps.put(_outbox('upsert', row.uuid, {'id': row.uuid, ...changes}, now));
    });
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

  @override
  Future<void> restore(String id) async {
    final now = _now();
    await _isar.writeTxn(() async {
      final row = await _isar.localTransactions.where().uuidEqualTo(id).findFirst();
      if (row == null || row.deletedAt == null) return;
      row
        ..deletedAt = null
        ..updatedAt = now;
      await _isar.localTransactions.put(row);
      await _isar.outboxOps.put(_outbox('upsert', id, {'id': id, 'deleted_at': null}, now));
    });
  }

  Future<Set<String>> _automaticSourceIds() async {
    final sources = await _isar.localSources.where().findAll();
    return {
      for (final s in sources)
        if (_automaticSources.contains(s.type)) s.uuid,
    };
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

  static Txn _toDomain(LocalTransaction t, Set<String> automaticSources) => Txn(
    id: t.uuid,
    accountId: t.accountId,
    type: TransactionType.values.byName(t.type),
    amount: t.amount,
    fee: t.fee,
    currency: t.currency,
    occurredAt: t.occurredAt,
    counterpartyName: t.counterpartyName,
    categoryId: t.categoryId,
    categorySource: t.categorySource,
    description: t.description,
    notes: t.notes,
    referenceId: t.referenceId,
    status: switch (t.status) {
      'pending' => TransactionStatus.pending,
      'needs_review' => TransactionStatus.needsReview,
      _ => TransactionStatus.confirmed,
    },
    isAutomatic: t.sourceId != null && automaticSources.contains(t.sourceId),
  );
}

import 'dart:convert';

import 'package:isar_community/isar.dart';
import 'package:uuid/uuid.dart';

import '../../domain/counterparty.dart';
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

  /// Saves just the reason/note. Unlike [update] it leaves a transaction that
  /// needs review in the queue: a note says nothing about the category.
  Future<void> updateNotes(String id, String? notes);

  /// Soft delete; [restore] undoes it.
  Future<void> delete(String id);
  Future<void> restore(String id);

  /// Other live transactions with the same person or shop (same account
  /// number or name), newest first. Empty when [txn] has neither.
  Stream<List<Txn>> watchRelated(Txn txn);

  /// The category the user last chose for this person or shop, if any.
  Future<String?> learnedCategory({String? name, String? account});

  /// Gives automatic transactions still waiting for review the category the
  /// user already taught for their person or shop. Returns how many changed.
  Future<int> applyLearnedCategories();

  /// Captured transactions whose bank receipt hasn't been read yet, newest
  /// first, with their account's institution.
  Future<List<({Txn txn, String institution})>> receiptCandidates({required DateTime since, int limit = 10});

  /// Fills only the empty fields from the receipt and marks it read.
  Future<void> applyReceipt(String id, {String? reason, String? counterpartyName, String? counterpartyAccount});

  /// Records a failed read; after [maxAttempts] the receipt is given up on.
  Future<void> receiptFailed(String id, {int maxAttempts = 3});
}

class IsarTransactionRepository extends TransactionRepository {
  IsarTransactionRepository(this._isar, {Uuid? uuid, DateTime Function()? clock, String? Function()? userId})
    : _uuid = uuid ?? const Uuid(),
      _now = clock ?? DateTime.now,
      _userId = userId ?? (() => null);

  final Isar _isar;
  final Uuid _uuid;
  final DateTime Function() _now;

  /// The signed-in user, for categorization rules; null when local-only.
  final String? Function() _userId;

  /// Category sources that came from the user, directly or via a rule they taught.
  static const _taught = {'user', 'rule'};

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
      final categoryChanged = row.categoryId != edited.categoryId;
      if (categoryChanged) {
        row
          ..categoryId = edited.categoryId
          ..categorySource = 'user';
        changes['category_id'] = edited.categoryId;
        changes['category_source'] = 'user';
      }
      if (changes.isEmpty) return;
      if (categoryChanged && edited.categoryId != null) await _teach(row, edited.categoryId!, now);

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
  Future<void> updateNotes(String id, String? notes) async {
    final text = notes == null || notes.trim().isEmpty ? null : notes.trim();
    final now = _now();
    await _isar.writeTxn(() async {
      final row = await _isar.localTransactions.where().uuidEqualTo(id).findFirst();
      if (row == null || row.deletedAt != null || row.notes == text) return;
      row
        ..notes = text
        ..updatedAt = now;
      await _isar.localTransactions.put(row);
      await _isar.outboxOps.put(_outbox('upsert', id, {'id': id, 'notes': text}, now));
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

  @override
  Stream<List<Txn>> watchRelated(Txn txn) {
    if (nameKey(txn.counterpartyName) == null && accountKey(txn.counterpartyAccount) == null) {
      return Stream.value(const []);
    }
    return _isar.localTransactions
        .filter()
        .deletedAtIsNull()
        .not()
        .uuidEqualTo(txn.id)
        .sortByOccurredAtDesc()
        .watch(fireImmediately: true)
        .asyncMap((rows) async {
          final automatic = await _automaticSourceIds();
          return [
            for (final r in rows)
              if (_matches(r, txn.counterpartyName, txn.counterpartyAccount)) _toDomain(r, automatic),
          ];
        });
  }

  @override
  Future<String?> learnedCategory({String? name, String? account}) async {
    if (nameKey(name) == null && accountKey(account) == null) return null;
    final rows = await _isar.localTransactions
        .filter()
        .deletedAtIsNull()
        .categoryIdIsNotNull()
        .anyOf(_taught, (q, String s) => q.categorySourceEqualTo(s))
        .sortByUpdatedAtDesc()
        .findAll();
    return rows.where((r) => _matches(r, name, account)).firstOrNull?.categoryId;
  }

  @override
  Future<int> applyLearnedCategories() async {
    final waiting = await _isar.localTransactions.filter().deletedAtIsNull().statusEqualTo('needs_review').findAll();
    var changed = 0;
    for (final row in waiting) {
      if (_taught.contains(row.categorySource)) continue;
      final category = await learnedCategory(name: row.counterpartyName, account: row.counterpartyAccount);
      if (category == null) continue;
      final now = _now();
      await _isar.writeTxn(() async {
        _learn(row, category);
        row.updatedAt = now;
        await _isar.localTransactions.put(row);
        await _isar.outboxOps.put(_outbox('upsert', row.uuid, _learnedPayload(row), now));
      });
      changed++;
    }
    return changed;
  }

  @override
  Future<List<({Txn txn, String institution})>> receiptCandidates({required DateTime since, int limit = 10}) async {
    final automatic = await _automaticSourceIds();
    if (automatic.isEmpty) return const [];
    final rows = await _isar.localTransactions
        .filter()
        .deletedAtIsNull()
        .receiptCheckedAtIsNull()
        .referenceIdIsNotNull()
        .occurredAtGreaterThan(since)
        .anyOf(automatic, (q, String id) => q.sourceIdEqualTo(id))
        .sortByOccurredAtDesc()
        .limit(limit)
        .findAll();
    final accounts = {for (final a in await _isar.localAccounts.where().findAll()) a.uuid: a.institution};
    return [for (final r in rows) (txn: _toDomain(r, automatic), institution: accounts[r.accountId] ?? 'other')];
  }

  @override
  Future<void> applyReceipt(String id, {String? reason, String? counterpartyName, String? counterpartyAccount}) async {
    final now = _now();
    await _isar.writeTxn(() async {
      final row = await _isar.localTransactions.where().uuidEqualTo(id).findFirst();
      if (row == null) return;
      row.receiptCheckedAt = now;
      final changes = <String, Object?>{};
      // Never overwrite what the user typed or the SMS already said.
      if (row.notes == null && _present(reason)) changes['notes'] = row.notes = reason!.trim();
      if (row.counterpartyName == null && _present(counterpartyName)) {
        changes['counterparty_name'] = row.counterpartyName = counterpartyName!.trim();
      }
      if (row.counterpartyAccount == null && _present(counterpartyAccount)) {
        changes['counterparty_account'] = row.counterpartyAccount = accountKey(counterpartyAccount);
      }
      if (changes.isNotEmpty) {
        row.updatedAt = now;
        await _isar.outboxOps.put(_outbox('upsert', id, {'id': id, ...changes}, now));
      }
      await _isar.localTransactions.put(row);
    });
  }

  @override
  Future<void> receiptFailed(String id, {int maxAttempts = 3}) async {
    await _isar.writeTxn(() async {
      final row = await _isar.localTransactions.where().uuidEqualTo(id).findFirst();
      if (row == null) return;
      row.receiptAttempts += 1;
      if (row.receiptAttempts >= maxAttempts) row.receiptCheckedAt = _now();
      await _isar.localTransactions.put(row);
    });
  }

  static bool _present(String? s) => s != null && s.trim().isNotEmpty;

  static bool _matches(LocalTransaction r, String? name, String? account) =>
      sameCounterparty(nameA: r.counterpartyName, accountA: r.counterpartyAccount, nameB: name, accountB: account);

  void _learn(LocalTransaction row, String categoryId) => row
    ..categoryId = categoryId
    ..categorySource = 'rule'
    ..status = 'confirmed'
    ..reviewReason = null;

  static Map<String, Object?> _learnedPayload(LocalTransaction row) => {
    'id': row.uuid,
    'category_id': row.categoryId,
    'category_source': 'rule',
    'status': 'confirmed',
    'review_reason': null,
  };

  /// The user chose [categoryId] for [row]: remember it for this person or
  /// shop. Writes the server rules (so future SMS arrive categorized) and
  /// sorts the same counterparty's transactions still waiting for review.
  /// Runs inside the caller's write transaction.
  Future<void> _teach(LocalTransaction row, String categoryId, DateTime now) async {
    final userId = _userId();
    if (userId != null) {
      for (final (field, value) in [
        ('counterparty', nameKey(row.counterpartyName)),
        ('counterparty_account', accountKey(row.counterpartyAccount)),
      ]) {
        if (value == null) continue;
        // One id per (user, field, value), so re-teaching updates the same
        // rule instead of tripping the server's unique index.
        final ruleId = _uuid.v5(Namespace.url.value, 'finance-rule:$userId:$field:$value');
        await _isar.outboxOps.put(
          OutboxOp()
            ..table = 'categorization_rules'
            ..op = 'upsert'
            ..rowId = ruleId
            ..payload = jsonEncode({
              'id': ruleId,
              'user_id': userId,
              'match_field': field,
              'match_value': value,
              'category_id': categoryId,
              'source': 'user_correction',
              'deleted_at': null,
            })
            ..createdAt = now,
        );
      }
    }

    final waiting = await _isar.localTransactions
        .filter()
        .deletedAtIsNull()
        .statusEqualTo('needs_review')
        .not()
        .uuidEqualTo(row.uuid)
        .findAll();
    for (final other in waiting) {
      if (_taught.contains(other.categorySource) || !_matches(other, row.counterpartyName, row.counterpartyAccount)) {
        continue;
      }
      _learn(other, categoryId);
      other.updatedAt = now;
      await _isar.localTransactions.put(other);
      await _isar.outboxOps.put(_outbox('upsert', other.uuid, _learnedPayload(other), now));
    }
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
    counterpartyAccount: t.counterpartyAccount,
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

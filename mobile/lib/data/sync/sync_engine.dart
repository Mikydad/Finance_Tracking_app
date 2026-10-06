import 'dart:async';
import 'dart:convert';

import 'package:isar_community/isar.dart';

import '../local/models.dart';
import 'sync_api.dart';

class SyncReport {
  const SyncReport({this.pushed = 0, this.rejected = 0, this.pulled = 0});

  /// Outbox ops the server accepted (and that were removed locally).
  final int pushed;

  /// Outbox ops the server refused; they stay queued with the error.
  final int rejected;

  /// Server rows written to the local database.
  final int pulled;
}

/// Moves changes between Isar and Supabase: push the outbox, then pull
/// everything newer than the stored cursor (build plan 2.7).
///
/// A row with an op still in the outbox keeps its local version on pull: the
/// local change wins until the server accepts it, and the accepted write then
/// comes back with a newer server_version on a later pull.
class SyncEngine {
  SyncEngine(this._isar, this._api, {this.pushBatchSize = 200, this.pullPageSize = 500, DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final Isar _isar;
  final SyncApi _api;
  final int pushBatchSize;
  final int pullPageSize;
  final DateTime Function() _now;

  Future<SyncReport>? _running;
  bool _rerun = false;

  /// Push then pull. A call made while a sync is running joins it, and the
  /// run repeats once so changes made in the meantime aren't left behind.
  Future<SyncReport> sync() async {
    if (_running != null) {
      _rerun = true;
      return _running!;
    }
    final run = _runUntilSettled();
    _running = run;
    try {
      return await run;
    } finally {
      _running = null;
    }
  }

  Future<SyncReport> _runUntilSettled() async {
    var pushed = 0, rejected = 0, pulled = 0;
    do {
      _rerun = false;
      final (accepted, refused) = await push();
      pushed += accepted;
      rejected = refused;
      pulled += await pull();
    } while (_rerun);
    return SyncReport(pushed: pushed, rejected: rejected, pulled: pulled);
  }

  /// Sends the outbox oldest first, in batches. Accepted ops are removed;
  /// rejected ones stay with their error and are retried on the next sync.
  /// Returns (accepted, rejected).
  Future<(int, int)> push() async {
    var accepted = 0;
    var rejected = 0;
    var after = -1;
    while (true) {
      final ops = await _isar.outboxOps.where().idGreaterThan(after).limit(pushBatchSize).findAll();
      if (ops.isEmpty) break;

      final results = await _api.push([
        for (final o in ops) {'table': o.table, 'op': o.op, 'row': jsonDecode(o.payload)},
      ]);
      if (results.length != ops.length) {
        throw StateError('sync_push returned ${results.length} results for ${ops.length} ops');
      }

      await _isar.writeTxn(() async {
        for (var i = 0; i < ops.length; i++) {
          if (results[i].ok) {
            await _isar.outboxOps.delete(ops[i].id);
            accepted++;
          } else {
            ops[i]
              ..attempts += 1
              ..lastError = results[i].error;
            await _isar.outboxOps.put(ops[i]);
            rejected++;
          }
        }
      });
      after = ops.last.id;
    }
    return (accepted, rejected);
  }

  /// Pulls every page newer than the stored cursor. The cursor is saved with
  /// each page, so an interrupted pull resumes where it stopped.
  Future<int> pull() async {
    var applied = 0;
    var cursor = (await _isar.syncStates.get(0))?.cursor ?? 0;
    while (true) {
      final page = await _api.pull(cursor, pullPageSize);
      await _isar.writeTxn(() async {
        final pending = {for (final o in await _isar.outboxOps.where().findAll()) o.rowId};
        for (final change in page.changes) {
          if (pending.contains(change.row['id'])) continue;
          if (await _apply(change)) applied++;
        }
        await _isar.syncStates.put(
          SyncState()
            ..cursor = page.cursor
            ..lastPulledAt = _now(),
        );
      });
      cursor = page.cursor;
      if (!page.hasMore) break;
    }
    return applied;
  }

  /// Number of local changes the server hasn't accepted yet.
  Future<int> pendingCount() => _isar.outboxOps.count();

  Future<bool> _apply(RemoteChange change) async {
    final r = change.row;
    final id = r['id'] as String;
    switch (change.table) {
      case 'transactions':
        final t = await _isar.localTransactions.getByUuid(id) ?? (LocalTransaction()..uuid = id);
        t
          ..accountId = r['account_id'] as String
          ..type = r['type'] as String
          ..amount = (r['amount'] as num).toInt()
          ..fee = (r['fee'] as num? ?? 0).toInt()
          ..currency = (r['currency'] as String? ?? 'ETB').trim()
          ..occurredAt = DateTime.parse(r['occurred_at'] as String)
          ..sourceId = r['source_id'] as String?
          ..counterpartyName = r['counterparty_name'] as String? ?? r['merchant_name'] as String?
          ..counterpartyKind = r['counterparty_kind'] as String?
          ..categoryId = r['category_id'] as String?
          ..categorySource = r['category_source'] as String?
          ..description = r['description'] as String?
          ..notes = r['notes'] as String?
          ..referenceId = r['reference_id'] as String?
          ..status = r['status'] as String? ?? 'confirmed'
          ..reviewReason = r['review_reason'] as String?
          ..deletedAt = _date(r['deleted_at'])
          ..serverVersion = (r['server_version'] as num).toInt()
          ..updatedAt = _date(r['updated_at']) ?? _now();
        await _isar.localTransactions.put(t);
      case 'categories':
        final c = await _isar.localCategorys.getByUuid(id) ?? (LocalCategory()..uuid = id);
        c
          ..userId = r['user_id'] as String?
          ..parentId = r['parent_id'] as String?
          ..key = r['key'] as String?
          ..name = r['name'] as String
          ..icon = r['icon'] as String?
          ..color = r['color'] as String?
          ..kind = r['kind'] as String? ?? 'expense'
          ..sortOrder = (r['sort_order'] as num? ?? 0).toInt()
          ..isArchived = r['is_archived'] as bool? ?? false
          ..deletedAt = _date(r['deleted_at'])
          ..serverVersion = (r['server_version'] as num).toInt();
        await _isar.localCategorys.put(c);
      case 'financial_accounts':
        final a = await _isar.localAccounts.getByUuid(id) ?? (LocalAccount()..uuid = id);
        a
          ..name = r['name'] as String
          ..institution = r['institution'] as String? ?? 'other'
          ..maskedNumber = r['masked_number'] as String?
          ..currency = (r['currency'] as String? ?? 'ETB').trim()
          ..isActive = r['is_active'] as bool? ?? true
          ..deletedAt = _date(r['deleted_at'])
          ..serverVersion = (r['server_version'] as num).toInt();
        await _isar.localAccounts.put(a);
      case 'transaction_sources':
        final src = await _isar.localSources.getByUuid(id) ?? (LocalSource()..uuid = id);
        src
          ..type = r['type'] as String? ?? 'other'
          ..deletedAt = _date(r['deleted_at'])
          ..serverVersion = (r['server_version'] as num).toInt();
        await _isar.localSources.put(src);
      default:
        // Profiles and rules aren't stored on the phone yet.
        return false;
    }
    return true;
  }

  static DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);
}

/// Wipes everything local, e.g. on sign-out so the next account starts clean.
Future<void> clearLocalData(Isar isar) => isar.writeTxn(isar.clear);

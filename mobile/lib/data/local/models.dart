import 'package:isar_community/isar.dart';

part 'models.g.dart';

// Local mirrors of the synced Supabase tables. `uuid` is the row id shared
// with the server; `serverVersion` is what the last pull saw (0 = never
// synced). Amounts are santim.

@collection
class LocalTransaction {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String uuid;

  @Index()
  late String accountId;

  /// expense | income | transfer
  late String type;
  late int amount;
  int fee = 0;
  String currency = 'ETB';

  @Index()
  late DateTime occurredAt;

  /// transaction_sources id: tells SMS/Shortcut captures from manual ones.
  String? sourceId;

  String? counterpartyName;
  String? counterpartyKind;
  String? categoryId;
  String? categorySource;
  String? description;
  String? notes;
  String? referenceId;

  /// pending | confirmed | needs_review
  String status = 'confirmed';
  String? reviewReason;

  DateTime? deletedAt;
  int serverVersion = 0;
  late DateTime updatedAt;
}

@collection
class LocalCategory {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String uuid;

  /// null = built-in default
  String? userId;
  String? parentId;
  String? key;
  late String name;
  String? icon;
  String? color;
  String kind = 'expense';
  int sortOrder = 0;
  bool isArchived = false;
  DateTime? deletedAt;
  int serverVersion = 0;
}

@collection
class LocalAccount {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String uuid;

  late String name;
  late String institution;
  String? maskedNumber;
  String currency = 'ETB';
  bool isActive = true;
  DateTime? deletedAt;
  int serverVersion = 0;
}

/// Where transactions come from (manual, sms, shortcut, ...). Read-only on
/// the phone; used to label transactions as automatic or manual.
@collection
class LocalSource {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String uuid;

  /// manual | sms | shortcut | bank | other
  late String type;
  DateTime? deletedAt;
  int serverVersion = 0;
}

/// A local write waiting to be pushed with sync_push. Written in the same
/// Isar transaction as the change itself, so nothing is lost offline.
@collection
class OutboxOp {
  Id id = Isar.autoIncrement;

  /// Supabase table name, e.g. "transactions".
  late String table;

  /// upsert | delete
  late String op;

  late String rowId;

  /// JSON of the changed columns (snake_case, as the server expects).
  late String payload;

  late DateTime createdAt;
  int attempts = 0;
  String? lastError;
}

/// Single row holding the pull cursor.
@collection
class SyncState {
  Id id = 0;
  int cursor = 0;
  DateTime? lastPulledAt;
}

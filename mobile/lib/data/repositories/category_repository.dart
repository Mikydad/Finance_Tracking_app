import 'dart:convert';

import 'package:isar_community/isar.dart';
import 'package:uuid/uuid.dart';

import '../../domain/category.dart';
import '../local/models.dart';

/// Built-in and custom categories, synced from the server. Only custom
/// categories (the user's own) can be changed; built-in ones are shared.
abstract class CategoryRepository {
  /// Live categories in display order; archived ones only when asked, e.g.
  /// to show the category of an old transaction.
  Stream<List<Category>> watchAll({bool includeArchived = false});

  /// Creates a custom category owned by [userId] and queues it for sync.
  Future<Category> add({
    required String userId,
    required String name,
    CategoryKind kind = CategoryKind.expense,
    String? parentId,
    String? icon,
    String? color,
  });

  Future<void> rename(String id, String name);

  /// Hides a custom category from pickers; transactions keep it.
  Future<void> setArchived(String id, bool archived);
}

class IsarCategoryRepository implements CategoryRepository {
  IsarCategoryRepository(this._isar, {Uuid? uuid, DateTime Function()? clock})
    : _uuid = uuid ?? const Uuid(),
      _now = clock ?? DateTime.now;

  final Isar _isar;
  final Uuid _uuid;
  final DateTime Function() _now;

  /// Custom categories sort after the built-in ones (which go up to 120).
  static const _customSortOrder = 500;

  @override
  Stream<List<Category>> watchAll({bool includeArchived = false}) {
    return _isar.localCategorys
        .filter()
        .deletedAtIsNull()
        .optional(!includeArchived, (q) => q.isArchivedEqualTo(false))
        .sortBySortOrder()
        .thenByName()
        .watch(fireImmediately: true)
        .map((rows) => rows.map(_toDomain).toList());
  }

  @override
  Future<Category> add({
    required String userId,
    required String name,
    CategoryKind kind = CategoryKind.expense,
    String? parentId,
    String? icon,
    String? color,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name', 'must not be empty');
    final row = LocalCategory()
      ..uuid = _uuid.v7()
      ..userId = userId
      ..parentId = parentId
      ..name = trimmed
      ..icon = icon
      ..color = color
      ..kind = kind.name
      ..sortOrder = _customSortOrder;
    await _isar.writeTxn(() async {
      await _isar.localCategorys.put(row);
      await _queue(row.uuid, {
        'id': row.uuid,
        'user_id': userId,
        'parent_id': parentId,
        'name': trimmed,
        'icon': icon,
        'color': color,
        'kind': kind.name,
        'sort_order': _customSortOrder,
      });
    });
    return _toDomain(row);
  }

  @override
  Future<void> rename(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name', 'must not be empty');
    return _changeCustom(id, (row) {
      if (row.name == trimmed) return null;
      row.name = trimmed;
      return {'name': trimmed};
    });
  }

  @override
  Future<void> setArchived(String id, bool archived) => _changeCustom(id, (row) {
    if (row.isArchived == archived) return null;
    row.isArchived = archived;
    return {'is_archived': archived};
  });

  Future<void> _changeCustom(String id, Map<String, Object?>? Function(LocalCategory row) change) async {
    await _isar.writeTxn(() async {
      final row = await _isar.localCategorys.getByUuid(id);
      if (row == null) return;
      if (row.userId == null) throw StateError('Built-in categories can\'t be changed');
      final changes = change(row);
      if (changes == null) return;
      await _isar.localCategorys.put(row);
      await _queue(id, {'id': id, ...changes});
    });
  }

  Future<void> _queue(String id, Map<String, Object?> payload) => _isar.outboxOps.put(
    OutboxOp()
      ..table = 'categories'
      ..op = 'upsert'
      ..rowId = id
      ..payload = jsonEncode(payload)
      ..createdAt = _now(),
  );

  static Category _toDomain(LocalCategory c) => Category(
    id: c.uuid,
    name: c.name,
    key: c.key,
    parentId: c.parentId,
    icon: c.icon,
    color: c.color,
    kind: CategoryKind.values.asNameMap()[c.kind] ?? CategoryKind.expense,
    isCustom: c.userId != null,
    isArchived: c.isArchived,
  );
}

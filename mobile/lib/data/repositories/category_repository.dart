import 'package:isar_community/isar.dart';

import '../../domain/category.dart';
import '../local/models.dart';

/// Built-in and custom categories, synced from the server. Adding and
/// renaming custom categories comes with the categories screen (task 2.4).
abstract class CategoryRepository {
  /// Live categories that aren't archived, in display order.
  Stream<List<Category>> watchAll();
}

class IsarCategoryRepository implements CategoryRepository {
  IsarCategoryRepository(this._isar);

  final Isar _isar;

  @override
  Stream<List<Category>> watchAll() {
    return _isar.localCategorys
        .filter()
        .deletedAtIsNull()
        .isArchivedEqualTo(false)
        .sortBySortOrder()
        .thenByName()
        .watch(fireImmediately: true)
        .map((rows) => rows.map(_toDomain).toList());
  }

  static Category _toDomain(LocalCategory c) => Category(
    id: c.uuid,
    name: c.name,
    key: c.key,
    parentId: c.parentId,
    icon: c.icon,
    color: c.color,
    kind: CategoryKind.values.asNameMap()[c.kind] ?? CategoryKind.expense,
    isCustom: c.userId != null,
  );
}

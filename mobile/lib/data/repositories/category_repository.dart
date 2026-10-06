import 'package:isar_community/isar.dart';

import '../../domain/category.dart';
import '../local/models.dart';

/// Built-in and custom categories, synced from the server. Adding and
/// renaming custom categories comes with the categories screen (task 2.4).
abstract class CategoryRepository {
  /// Live categories in display order; archived ones only when asked, e.g.
  /// to show the category of an old transaction.
  Stream<List<Category>> watchAll({bool includeArchived = false});
}

class IsarCategoryRepository implements CategoryRepository {
  IsarCategoryRepository(this._isar);

  final Isar _isar;

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

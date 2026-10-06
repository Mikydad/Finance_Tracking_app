enum CategoryKind { expense, income, both }

class Category {
  const Category({
    required this.id,
    required this.name,
    this.key,
    this.parentId,
    this.icon,
    this.color,
    this.kind = CategoryKind.expense,
    this.isCustom = false,
  });

  final String id;
  final String name;

  /// Stable key of a built-in category, e.g. `food.coffee`; null for custom ones.
  final String? key;
  final String? parentId;
  final String? icon;
  final String? color;
  final CategoryKind kind;

  /// Created by the user rather than one of the built-in defaults.
  final bool isCustom;
}

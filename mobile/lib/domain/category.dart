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
    this.isArchived = false,
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

  /// Hidden from pickers, still shown on old transactions.
  final bool isArchived;

  bool get isTopLevel => parentId == null;

  /// Whether it makes sense for a transaction of this kind.
  bool fits(String transactionType) => switch (transactionType) {
    'expense' => kind != CategoryKind.income,
    'income' => kind != CategoryKind.expense,
    _ => true,
  };
}

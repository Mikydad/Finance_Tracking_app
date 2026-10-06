import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../domain/category.dart';

/// Rounded colored square with the category's icon, as in the UI concept.
class CategoryIcon extends StatelessWidget {
  const CategoryIcon(this.category, {super.key, this.size = 40, this.parent});

  final Category? category;

  /// Used for the color when [category] is a custom child without its own.
  final Category? parent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = category;
    final style = c == null
        ? CategoryStyle.uncategorized
        : CategoryStyle.of(key: c.key ?? parent?.key, icon: c.icon ?? parent?.icon, color: c.color ?? parent?.color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: style.color, borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(style.icon, color: Colors.white, size: size * 0.55),
    );
  }
}

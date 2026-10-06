import 'package:flutter/material.dart';

/// Look and feel from the UI concept (docs/ui-concept.png): deep green
/// primary, light background, rounded white cards, colorful category icons.
abstract final class AppColors {
  static const primary = Color(0xFF0E4F3B);
  static const primarySoft = Color(0xFFE3F2EA);
  static const background = Color(0xFFF6F7F6);
  static const surface = Colors.white;
  static const border = Color(0xFFE8EBE9);
  static const text = Color(0xFF17201B);
  static const muted = Color(0xFF6B7470);
  static const income = Color(0xFF1F9D55);
  static const danger = Color(0xFFD64545);
}

abstract final class AppRadii {
  static const card = 16.0;
  static const button = 14.0;
  static const chip = 20.0;
  static const icon = 12.0;
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    surface: AppColors.surface,
    error: AppColors.danger,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final text = base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text);
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.button));

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: rounded,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: rounded),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.button),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.button),
        borderSide: const BorderSide(color: AppColors.border),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.chip)),
      side: const BorderSide(color: AppColors.border),
      showCheckmark: false,
      selectedColor: AppColors.primary,
      secondaryLabelStyle: const TextStyle(color: Colors.white),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppColors.primary,
        selectedForegroundColor: Colors.white,
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primarySoft,
      height: 68,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
  );
}

/// Icon and color for a category, from its built-in key (children use their
/// parent's color) or the icon name stored with it.
class CategoryStyle {
  const CategoryStyle(this.icon, this.color);

  final IconData icon;
  final Color color;

  static const _byRootKey = <String, CategoryStyle>{
    'food': CategoryStyle(Icons.restaurant, Color(0xFFF28C38)),
    'transport': CategoryStyle(Icons.directions_car, Color(0xFF2F80ED)),
    'shopping': CategoryStyle(Icons.shopping_bag, Color(0xFFEC5C9A)),
    'bills': CategoryStyle(Icons.receipt_long, Color(0xFF27AE60)),
    'entertainment': CategoryStyle(Icons.sports_esports, Color(0xFF8E59E8)),
    'health': CategoryStyle(Icons.favorite, Color(0xFFEB5757)),
    'education': CategoryStyle(Icons.school, Color(0xFF2D6CDF)),
    'family': CategoryStyle(Icons.family_restroom, Color(0xFFF2A93B)),
    'subscriptions': CategoryStyle(Icons.autorenew, Color(0xFFD6457A)),
    'income': CategoryStyle(Icons.payments, AppColors.income),
    'transfer': CategoryStyle(Icons.swap_horiz, Color(0xFF13A3A3)),
    'other': CategoryStyle(Icons.more_horiz, Color(0xFF7C8580)),
  };

  static const _childIcons = <String, IconData>{
    'food.restaurants': Icons.restaurant,
    'food.groceries': Icons.local_grocery_store,
    'food.coffee': Icons.local_cafe,
    'transport.taxi': Icons.local_taxi,
    'transport.fuel': Icons.local_gas_station,
    'transport.public': Icons.directions_bus,
    'bills.internet': Icons.wifi,
    'bills.phone': Icons.phone_iphone,
    'bills.electricity': Icons.bolt,
  };

  static const _byIconName = <String, IconData>{
    'restaurant': Icons.restaurant,
    'directions_car': Icons.directions_car,
    'shopping_bag': Icons.shopping_bag,
    'receipt': Icons.receipt_long,
    'movie': Icons.movie,
    'favorite': Icons.favorite,
    'school': Icons.school,
    'family': Icons.family_restroom,
    'autorenew': Icons.autorenew,
    'payments': Icons.payments,
    'swap_horiz': Icons.swap_horiz,
    'more_horiz': Icons.more_horiz,
    ...customIcons,
  };

  /// Icons offered for custom categories, by the name stored on the server.
  static const customIcons = <String, IconData>{
    'label': Icons.label_outline,
    'home': Icons.home_outlined,
    'pets': Icons.pets,
    'gift': Icons.card_giftcard,
    'fitness': Icons.fitness_center,
    'travel': Icons.flight,
    'child': Icons.child_care,
    'church': Icons.church,
    'savings': Icons.savings_outlined,
    'work': Icons.work_outline,
    'clothes': Icons.checkroom,
    'drinks': Icons.local_bar,
    'beauty': Icons.spa_outlined,
    'phone': Icons.phone_iphone,
    'sport': Icons.sports_soccer,
    'charity': Icons.volunteer_activism,
  };

  /// Colors offered for custom categories, stored as "#RRGGBB".
  static const customColors = [
    '#F28C38', '#EC5C9A', '#2F80ED', '#27AE60', '#8E59E8', '#EB5757', //
    '#13A3A3', '#F2A93B', '#D6457A', '#2D6CDF', '#7C8580', '#0E4F3B',
  ];

  static const uncategorized = CategoryStyle(Icons.help_outline, Color(0xFF9AA3A0));

  static CategoryStyle of({String? key, String? icon, String? color}) {
    if (key != null) {
      final root = _byRootKey[key.split('.').first];
      if (root != null) return CategoryStyle(_childIcons[key] ?? root.icon, root.color);
    }
    return CategoryStyle(_byIconName[icon] ?? Icons.label_outline, _parseHex(color) ?? _byRootKey['other']!.color);
  }

  static Color? _parseHex(String? hex) {
    if (hex == null) return null;
    final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }
}

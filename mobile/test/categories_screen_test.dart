import 'dart:async';

import 'package:finance_app/core/config.dart';
import 'package:finance_app/core/theme.dart';
import 'package:finance_app/data/repositories/category_repository.dart';
import 'package:finance_app/domain/category.dart';
import 'package:finance_app/features/categories/categories_screen.dart';
import 'package:finance_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCategories implements CategoryRepository {
  final rows = <Category>[
    const Category(id: 'cat-food', key: 'food', name: 'Food'),
    const Category(id: 'cat-coffee', key: 'food.coffee', name: 'Coffee', parentId: 'cat-food'),
  ];
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<List<Category>> watchAll({bool includeArchived = false}) async* {
    List<Category> read() => rows.where((c) => includeArchived || !c.isArchived).toList();
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
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
    final c = Category(id: 'new', name: name, kind: kind, icon: icon, color: color, isCustom: true);
    rows.add(c);
    _changes.add(null);
    return c;
  }

  @override
  Future<void> rename(String id, String name) async {}

  @override
  Future<void> setArchived(String id, bool archived) async {
    final i = rows.indexWhere((c) => c.id == id);
    final c = rows[i];
    rows[i] = Category(id: c.id, name: c.name, icon: c.icon, color: c.color, isCustom: true, isArchived: archived);
    _changes.add(null);
  }
}

void main() {
  testWidgets('add a custom category, archive it, restore it', (tester) async {
    final repo = FakeCategories();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configProvider.overrideWithValue(const AppConfig(supabaseUrl: '', supabasePublishableKey: '')),
          categoryRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: const CategoriesScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Coffee'), findsOneWidget, reason: 'children listed under their parent');

    await tester.tap(find.byKey(const Key('add-category')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('category-name')), 'Church');
    await tester.tap(find.byKey(const Key('save-category')));
    await tester.pumpAndSettle();
    expect(repo.rows.last.name, 'Church');
    expect(repo.rows.last.icon, isNotNull);
    expect(find.text('Church'), findsOneWidget);

    await tester.tap(find.byKey(const Key('menu-Church')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Archived'), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Archived'), findsNothing);
    expect(repo.rows.last.isArchived, isFalse);
  });
}

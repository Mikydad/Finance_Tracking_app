import 'dart:convert';
import 'dart:io';

import 'package:finance_app/data/local/models.dart';
import 'package:finance_app/data/repositories/category_repository.dart';
import 'package:finance_app/domain/category.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

import 'isar_helper.dart';

void main() {
  late Isar isar;
  late Directory dir;
  late IsarCategoryRepository repo;

  setUpAll(initIsarForTests);

  setUp(() async {
    (isar, dir) = await openTestIsar();
    repo = IsarCategoryRepository(isar, clock: () => DateTime.utc(2026, 10, 6));
    await isar.writeTxn(
      () => isar.localCategorys.put(
        LocalCategory()
          ..uuid = 'cat-food'
          ..key = 'food'
          ..name = 'Food'
          ..sortOrder = 10,
      ),
    );
  });

  tearDown(() => closeTestIsar(isar, dir));

  Future<List<Map<String, dynamic>>> payloads() async => [
    for (final o in await isar.outboxOps.where().findAll()) jsonDecode(o.payload) as Map<String, dynamic>,
  ];

  test('add creates a custom category after the built-ins and queues it with the owner', () async {
    final c = await repo.add(userId: 'user-1', name: '  Church ', icon: 'church', color: '#13A3A3');

    final list = await repo.watchAll().first;
    expect(list.map((c) => c.name), ['Food', 'Church']);
    expect(list.last.isCustom, isTrue);

    final p = (await payloads()).single;
    expect(p['id'], c.id);
    expect(p['user_id'], 'user-1');
    expect(p['name'], 'Church');
    expect(p['kind'], 'expense');
    expect(p['icon'], 'church');
  });

  test('rename and archive queue only what changed; archived ones leave the picker', () async {
    final c = await repo.add(userId: 'user-1', name: 'Gym');
    await repo.rename(c.id, 'Fitness');
    await repo.setArchived(c.id, true);
    await repo.setArchived(c.id, true); // no-op

    expect((await payloads()).skip(1), [
      {'id': c.id, 'name': 'Fitness'},
      {'id': c.id, 'is_archived': true},
    ]);
    expect((await repo.watchAll().first).map((c) => c.name), ['Food']);
    final withArchived = await repo.watchAll(includeArchived: true).first;
    expect(withArchived.singleWhere((x) => x.id == c.id).isArchived, isTrue);
  });

  test('built-in categories cannot be changed', () async {
    await expectLater(repo.rename('cat-food', 'Meals'), throwsStateError);
    expect(await isar.outboxOps.count(), 0);
  });

  test('a blank name is rejected', () {
    expect(() => repo.add(userId: 'u', name: '  ', kind: CategoryKind.income), throwsArgumentError);
  });
}

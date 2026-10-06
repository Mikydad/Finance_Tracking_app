import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

const localSchemas = [
  LocalTransactionSchema,
  LocalCategorySchema,
  LocalAccountSchema,
  LocalSourceSchema,
  OutboxOpSchema,
  SyncStateSchema,
];

Future<Isar> openLocalDb() async {
  final dir = await getApplicationDocumentsDirectory();
  return Isar.open(localSchemas, directory: dir.path, name: 'finance');
}

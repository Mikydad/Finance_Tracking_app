import 'package:isar_community/isar.dart';

import '../../domain/account.dart';
import '../local/models.dart';

/// Accounts come from the server: a Cash account is created at sign-up and
/// bank accounts appear when their first SMS is ingested.
abstract class AccountRepository {
  Stream<List<Account>> watchAll();

  /// The Cash account, used for manual entries when no other account is picked.
  Future<Account?> cash();
}

class IsarAccountRepository implements AccountRepository {
  IsarAccountRepository(this._isar);

  final Isar _isar;

  @override
  Stream<List<Account>> watchAll() {
    return _isar.localAccounts
        .filter()
        .deletedAtIsNull()
        .isActiveEqualTo(true)
        .sortByName()
        .watch(fireImmediately: true)
        .map((rows) => rows.map(_toDomain).toList());
  }

  @override
  Future<Account?> cash() async {
    final row = await _isar.localAccounts.filter().deletedAtIsNull().institutionEqualTo('cash').findFirst();
    return row == null ? null : _toDomain(row);
  }

  static Account _toDomain(LocalAccount a) =>
      Account(id: a.uuid, name: a.name, institution: a.institution, maskedNumber: a.maskedNumber, currency: a.currency);
}

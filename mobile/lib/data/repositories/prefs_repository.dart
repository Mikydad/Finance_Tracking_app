import 'package:isar_community/isar.dart';

import '../../core/periods.dart';
import '../local/models.dart';

/// Calendar and week-start choices, kept on this phone only.
class PrefsRepository {
  PrefsRepository(this._isar);

  final Isar _isar;

  Stream<CalendarPrefs> watch() => _isar.localPrefs.watchObject(0, fireImmediately: true).map(_toDomain).distinct();

  Future<void> save(CalendarPrefs prefs) => _isar.writeTxn(
    () => _isar.localPrefs.put(
      LocalPrefs()
        ..calendar = prefs.calendar.name
        ..weekStartsMonday = prefs.weekStartsMonday,
    ),
  );

  static CalendarPrefs _toDomain(LocalPrefs? row) => row == null
      ? const CalendarPrefs()
      : CalendarPrefs(
          calendar: row.calendar == 'ethiopian' ? CalendarKind.ethiopian : CalendarKind.gregorian,
          weekStartsMonday: row.weekStartsMonday,
        );
}

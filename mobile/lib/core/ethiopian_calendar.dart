/// Ethiopian (Ge'ez) calendar: 12 months of 30 days, then Pagume with 5 days
/// (6 in the year before a Gregorian leap year). New year, Meskerem 1, falls
/// on September 11 (September 12 before a Gregorian leap year).
///
/// Converted through the Julian Day Number, Amete Mihret era.
library;

const ethiopianMonths = [
  'Meskerem', 'Tikimt', 'Hidar', 'Tahsas', 'Tir', 'Yekatit', //
  'Megabit', 'Miyazia', 'Ginbot', 'Sene', 'Hamle', 'Nehase', 'Pagume',
];

const _epoch = 1723856; // JDN offset of the Amete Mihret era

typedef EthiopianDate = ({int year, int month, int day});

int _jdnFromGregorian(int y, int m, int d) => DateTime.utc(y, m, d).millisecondsSinceEpoch ~/ 86400000 + 2440588;

DateTime _gregorianFromJdn(int jdn) {
  final utc = DateTime.fromMillisecondsSinceEpoch((jdn - 2440588) * 86400000, isUtc: true);
  return DateTime(utc.year, utc.month, utc.day);
}

/// The Ethiopian date of [d]'s calendar day (time of day is ignored).
EthiopianDate toEthiopian(DateTime d) {
  final jdn = _jdnFromGregorian(d.year, d.month, d.day);
  final r = (jdn - _epoch) % 1461;
  final n = r % 365 + 365 * (r ~/ 1460);
  final year = 4 * ((jdn - _epoch) ~/ 1461) + r ~/ 365 - r ~/ 1460;
  return (year: year, month: n ~/ 30 + 1, day: n % 30 + 1);
}

/// Local midnight of an Ethiopian date. Out-of-range days roll over, so
/// month 14 day 1 is next year's Meskerem 1 (handy for "start of next month").
DateTime fromEthiopian(int year, int month, int day) {
  // Normalize month overflow either way (13 months a year); floor, not ~/,
  // so month 0 is the previous year's Pagume.
  final y = year + ((month - 1) / 13).floor();
  final m = (month - 1) % 13 + 1;
  final jdn = (_epoch + 365) + 365 * (y - 1) + y ~/ 4 + 30 * m + day - 31;
  return _gregorianFromJdn(jdn);
}

/// "Tikimt 28, 2019".
String ethiopianLabel(DateTime d, {bool withYear = true}) {
  final e = toEthiopian(d);
  final base = '${ethiopianMonths[e.month - 1]} ${e.day}';
  return withYear ? '$base, ${e.year}' : base;
}

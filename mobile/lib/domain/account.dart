/// A place money lives: a bank account, a telebirr wallet, or cash.
class Account {
  const Account({
    required this.id,
    required this.name,
    required this.institution,
    this.maskedNumber,
    this.currency = 'ETB',
  });

  final String id;
  final String name;

  /// cbe | cbo | abyssinia | awash | dashen | telebirr | cash | other
  final String institution;

  /// e.g. `****1234`; null for cash or before the bank's first SMS.
  final String? maskedNumber;
  final String currency;

  bool get isCash => institution == 'cash';
}

/// Money is stored as integer santim (2,500.00 ETB = 250000), matching the
/// backend. These helpers are the only place santim and birr meet.
library;

/// Formats santim as "2,500.00".
String formatBirr(int santim) {
  final negative = santim < 0;
  final abs = santim.abs();
  final whole = (abs ~/ 100).toString();
  final cents = (abs % 100).toString().padLeft(2, '0');
  final grouped = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${negative ? '-' : ''}$grouped.$cents';
}

/// Parses what a user types ("1500", "1,500.5", "1500.25") into santim.
/// Returns null for anything that isn't a positive amount with at most two
/// decimals.
int? parseBirr(String input) {
  final cleaned = input.replaceAll(',', '').trim();
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(cleaned);
  if (match == null) return null;
  final whole = int.parse(match.group(1)!);
  final fraction = int.parse((match.group(2) ?? '').padRight(2, '0'));
  final santim = whole * 100 + fraction;
  return santim > 0 ? santim : null;
}

/// Like [formatBirr] but drops ".00" for whole amounts: "2,500", "12.50".
String formatBirrCompact(int santim) {
  final full = formatBirr(santim);
  return full.endsWith('.00') ? full.substring(0, full.length - 3) : full;
}

/// Who is on the other side of a transaction, reduced to keys that let two
/// transactions be recognized as the same person or shop.
library;

/// Lowercase, punctuation-free name key. Must stay identical to `matchKey` in
/// supabase/functions/_shared/normalizer.ts: the server looks up the rules the
/// phone writes with it.
String? nameKey(String? raw) {
  if (raw == null) return null;
  final key = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ሀ-፿]+'), ' ').trim();
  return key.isEmpty ? null : key;
}

/// One shape for masked account numbers, whatever the source printed:
/// "1********3307" and "1000123453307" -> "****3307", "2519****1122" stays.
/// Mirrors `normalizeMasked` on the server for bank accounts; telebirr
/// numbers keep their prefix because the SMS and the receipt both show it.
String? accountKey(String? raw) {
  if (raw == null) return null;
  final compact = raw.replaceAll(RegExp(r'\s'), '');
  if (RegExp(r'^2519\*+\d{2,6}$').hasMatch(compact)) return compact;
  final masked = RegExp(r'\*+(\d{2,6})$').firstMatch(compact);
  if (masked != null) return '****${masked.group(1)}';
  final digits = compact.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 4) return null;
  return '****${digits.substring(digits.length - 4)}';
}

/// The same person or shop: same account number, or the same name.
bool sameCounterparty({String? nameA, String? accountA, String? nameB, String? accountB}) {
  final accA = accountKey(accountA), accB = accountKey(accountB);
  if (accA != null && accA == accB) return true;
  final keyA = nameKey(nameA), keyB = nameKey(nameB);
  return keyA != null && keyA == keyB;
}

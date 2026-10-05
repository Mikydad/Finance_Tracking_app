/// What the app works with; the Isar and Supabase shapes are mapped to and
/// from this in the repositories.
enum TransactionType { expense, income, transfer }

enum TransactionStatus { pending, confirmed, needsReview }

class Txn {
  const Txn({
    required this.id,
    required this.accountId,
    required this.type,
    required this.amount,
    required this.occurredAt,
    this.fee = 0,
    this.currency = 'ETB',
    this.counterpartyName,
    this.categoryId,
    this.notes,
    this.status = TransactionStatus.confirmed,
  });

  /// UUID generated on the device, so offline writes need no server round trip.
  final String id;
  final String accountId;
  final TransactionType type;

  /// Santim, always positive; [type] says which way it went.
  final int amount;
  final int fee;
  final String currency;
  final DateTime occurredAt;
  final String? counterpartyName;
  final String? categoryId;
  final String? notes;
  final TransactionStatus status;

  /// Money that left (or arrived in) the account, fees included.
  int get signedTotal => type == TransactionType.income ? amount : -(amount + fee);
}

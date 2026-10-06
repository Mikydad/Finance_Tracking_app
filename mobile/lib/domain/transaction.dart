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
    this.categorySource,
    this.description,
    this.notes,
    this.referenceId,
    this.status = TransactionStatus.confirmed,
    this.isAutomatic = false,
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

  /// How the category was chosen: user, rule, merchant_map, keyword, ai, fallback.
  final String? categorySource;

  /// What the bank said, e.g. "CBE Fast Loan repayment".
  final String? description;
  final String? notes;

  /// The bank's own transaction ID, when captured from an SMS.
  final String? referenceId;
  final TransactionStatus status;

  /// Captured from a bank SMS (Shortcut or paste) rather than typed in.
  final bool isAutomatic;

  /// Money that left (or arrived in) the account, fees included.
  int get signedTotal => type == TransactionType.income ? amount : -(amount + fee);

  /// A name to show when there's no counterparty.
  String get title =>
      counterpartyName ??
      description ??
      switch (type) {
        TransactionType.income => 'Income',
        TransactionType.transfer => 'Transfer',
        TransactionType.expense => 'Expense',
      };

  Txn copyWith({
    String? accountId,
    TransactionType? type,
    int? amount,
    DateTime? occurredAt,
    String? Function()? counterpartyName,
    String? Function()? categoryId,
    String? Function()? notes,
  }) => Txn(
    id: id,
    accountId: accountId ?? this.accountId,
    type: type ?? this.type,
    amount: amount ?? this.amount,
    occurredAt: occurredAt ?? this.occurredAt,
    fee: fee,
    currency: currency,
    counterpartyName: counterpartyName == null ? this.counterpartyName : counterpartyName(),
    categoryId: categoryId == null ? this.categoryId : categoryId(),
    categorySource: categorySource,
    description: description,
    notes: notes == null ? this.notes : notes(),
    referenceId: referenceId,
    status: status,
    isAutomatic: isAutomatic,
  );
}

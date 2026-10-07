import '../../domain/transaction.dart';
import '../repositories/transaction_repository.dart';
import 'receipt_reader.dart';

/// After each sync: reads the bank receipts of newly captured transactions
/// (reason, full name, account) and then gives transactions waiting for review
/// the category the user already taught for that person or shop.
///
/// Quiet by design: a receipt that can't be read is retried on later syncs
/// and given up after a few tries; nothing is shown to the user.
class ReceiptEnricher {
  ReceiptEnricher(this._repo, this._reader, {DateTime Function()? clock, this.window = const Duration(days: 30)})
    : _now = clock ?? DateTime.now;

  final TransactionRepository _repo;
  final ReceiptReader _reader;
  final DateTime Function() _now;

  /// Only receipts this recent are read (older links tend to expire).
  final Duration window;

  bool _running = false;

  Future<void> run() async {
    if (_running) return;
    _running = true;
    try {
      final candidates = await _repo.receiptCandidates(since: _now().subtract(window));
      for (final (:txn, :institution) in candidates) {
        final ref = txn.referenceId!;
        if (!ReceiptReader.supports(institution, ref)) {
          await _repo.applyReceipt(txn.id); // nothing to read; mark it done
          continue;
        }
        try {
          final details = await _reader.read(
            institution: institution,
            referenceId: ref,
            income: txn.type == TransactionType.income,
          );
          await _repo.applyReceipt(
            txn.id,
            reason: details.reason,
            counterpartyName: details.counterpartyName,
            counterpartyAccount: details.counterpartyAccount,
          );
        } on ReceiptUnavailable {
          await _repo.applyReceipt(txn.id);
        } catch (_) {
          await _repo.receiptFailed(txn.id);
        }
      }
      await _repo.applyLearnedCategories();
    } finally {
      _running = false;
    }
  }
}

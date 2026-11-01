import 'dart:convert';

import 'package:http/http.dart' as http;

/// What a bank receipt adds to an SMS: the reason the sender typed and the
/// other side's full name and (masked) account.
class ReceiptDetails {
  const ReceiptDetails({this.reason, this.counterpartyName, this.counterpartyAccount});

  final String? reason;
  final String? counterpartyName;
  final String? counterpartyAccount;

  bool get isEmpty => reason == null && counterpartyName == null && counterpartyAccount == null;
}

/// The receipt was there but held nothing useful, or the bank said no such
/// receipt: don't ask again.
class ReceiptUnavailable implements Exception {
  const ReceiptUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'ReceiptUnavailable: $reason';
}

/// Reads the receipt behind an SMS's link. Runs on the phone: telebirr's
/// receipt site only answers requests from Ethiopia, so the server can't.
///
/// telebirr: `https://transactioninfo.ethiotelecom.et/receipt/{transaction number}`
///   (an HTML page; the reason is "Customer Note").
/// CBE: `https://mbreciept.cbe.com.et/{v2-slug}` is a page that loads its data
///   from Mb.cbe.com.et; the reason is the payment details the sender typed.
/// Other banks aren't read yet.
class ReceiptReader {
  ReceiptReader({http.Client? client, this.timeout = const Duration(seconds: 15)}) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  static const _cbeHeaders = {
    // The headers CBE's own receipt page sends to its data endpoint.
    'X-App-ID': 'd1292e42-7400-49de-a2d3-9731caa4c819',
    'X-App-Version': '0a01980b-9859-1369-8198-59f403820000',
  };

  /// Whether a receipt exists to be read for this transaction.
  static bool supports(String institution, String referenceId) => switch (institution) {
    'telebirr' => RegExp(r'^[A-Z0-9]{8,12}$').hasMatch(referenceId),
    'cbe' => referenceId.startsWith('v2-'),
    _ => false,
  };

  /// Throws [ReceiptUnavailable] when there's nothing to read, and anything
  /// else (timeouts, no connection) when it's worth trying again later.
  Future<ReceiptDetails> read({required String institution, required String referenceId, required bool income}) async {
    switch (institution) {
      case 'telebirr':
        final res = await _client
            .get(Uri.https('transactioninfo.ethiotelecom.et', '/receipt/$referenceId'))
            .timeout(timeout);
        _check(res);
        return parseTelebirr(utf8.decode(res.bodyBytes, allowMalformed: true), income: income);
      case 'cbe':
        final res = await _client
            .get(
              Uri.https('mb.cbe.com.et', '/api/v1/transactions/public/transaction-detail/$referenceId'),
              headers: _cbeHeaders,
            )
            .timeout(timeout);
        _check(res);
        return parseCbe(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>, income: income);
      default:
        throw ReceiptUnavailable('no reader for $institution');
    }
  }

  static void _check(http.Response res) {
    if (res.statusCode == 404 || res.statusCode == 400) throw ReceiptUnavailable('HTTP ${res.statusCode}');
    if (res.statusCode != 200) throw http.ClientException('HTTP ${res.statusCode}');
  }

  /// The telebirr receipt is a two-column table of bilingual labels
  /// ("የደንበኛ መልዕክት/Customer Note") and values.
  static ReceiptDetails parseTelebirr(String html, {required bool income}) {
    String? field(String label) {
      final m = RegExp(
        '<td[^>]*>[^<]*${RegExp.escape(label)}[^<]*</td>\\s*<td[^>]*>(.*?)</td>',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(html);
      return m == null ? null : _clean(m.group(1)!);
    }

    if (!html.contains('telebirr')) throw const ReceiptUnavailable('not a telebirr receipt');
    final details = ReceiptDetails(
      reason: field('Customer Note'),
      counterpartyName: income ? field('Payer Name') : field('Credited Party name'),
      counterpartyAccount: income ? field('Payer telebirr no') : field('Credited party account no'),
    );
    if (details.isEmpty) throw const ReceiptUnavailable('telebirr receipt without details');
    return details;
  }

  static ReceiptDetails parseCbe(Map<String, dynamic> json, {required bool income}) {
    String? text(Object? v) => v is String ? _clean(v) : null;
    final paymentDetails = json['paymentDetails'];
    final reason =
        text(json['description']) ??
        (paymentDetails is List && paymentDetails.isNotEmpty ? text(paymentDetails.first) : null);
    final details = ReceiptDetails(
      reason: reason,
      counterpartyName: text(income ? json['debitAccountHolder'] : json['creditAccountHolder']),
      // Full account numbers come back; only the masked tail is kept.
      counterpartyAccount: _mask(text(income ? json['debitAccountNo'] : json['creditAccountNo'])),
    );
    if (details.isEmpty) throw const ReceiptUnavailable('CBE receipt without details');
    return details;
  }

  static String? _mask(String? account) {
    if (account == null) return null;
    final digits = account.replaceAll(RegExp(r'\D'), '');
    return digits.length < 4 ? null : '****${digits.substring(digits.length - 4)}';
  }

  /// Strips tags and entities; null for blanks and the banks' placeholders.
  static String? _clean(String raw) {
    final text = raw
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty || text == '-' || text.toUpperCase() == 'N/A' || text.toLowerCase() == 'null') return null;
    return text;
  }

  void close() => _client.close();
}

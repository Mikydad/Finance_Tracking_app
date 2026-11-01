import 'dart:convert';

import 'package:finance_app/data/receipts/receipt_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Shaped like the real telebirr receipt page (two-column bilingual table);
/// names and numbers are made up.
String telebirrHtml({String note = 'Overdraft'}) =>
    '''
<html><body><h2>telebirr receipt</h2>
<table class="auto-style1">
<tr> <td style="width: 390px; text-align: left;"> የከፋይ ስም/Payer Name </td> <td style="text-align: left"> Abebe Kebede Tadesse</td> </tr>
<tr> <td style="text-align: left; width: 300px;"> የከፋይ ቴሌብር ቁ./Payer telebirr no. </td> <td style="text-align: left"> 2519****8465</td> </tr>
<tr> <td style="text-align: left; width: 300px;"> የገንዘብ ተቀባይ ስም/Credited Party name </td> <td style="text-align: left"> Hana Girma Alemu</label></td> </tr>
<tr> <td class="auto-style3" style="text-align: left; width: 300px;"> የገንዘብ ተቀባይ ቴሌብር ቁ./Credited party account no </td> <td class="auto-style3" style="text-align: left"> 2519****1122 </td> </tr>
<tr> <td> የክፍያ ምክንያት/Payment Reason</td> <td class="auto-style18"> Send Money to Registered Customer </td> </tr>
<tr> <td>የደንበኛ መልዕክት/Customer Note</td> <td class="auto-style18" style="vertical-align:bottom"> $note </td> </tr>
</table></body></html>''';

/// Shaped like CBE's transaction-detail JSON; made-up values.
Map<String, dynamic> cbeJson({String? description = 'house rent october'}) => {
  'id': 'FT26274ABCDE',
  'debitAccountNo': '1000111122224758',
  'debitAccountHolder': 'Abebe Kebede Tadesse',
  'creditAccountNo': '1000333344446829',
  'creditAccountHolder': 'Dawit Fite Woyessa',
  'paymentDetails': ['house rent octob'],
  'description': description,
  'status': 'COMPLETED',
};

void main() {
  group('telebirr', () {
    test('expense: the note is the reason; the credited party is the counterparty', () {
      final d = ReceiptReader.parseTelebirr(telebirrHtml(), income: false);
      expect(d.reason, 'Overdraft');
      expect(d.counterpartyName, 'Hana Girma Alemu');
      expect(d.counterpartyAccount, '2519****1122');
    });

    test('income: the payer is the counterparty', () {
      final d = ReceiptReader.parseTelebirr(telebirrHtml(), income: true);
      expect(d.counterpartyName, 'Abebe Kebede Tadesse');
      expect(d.counterpartyAccount, '2519****8465');
    });

    test('an empty note gives no reason, never the generic "Payment Reason"', () {
      final d = ReceiptReader.parseTelebirr(telebirrHtml(note: ''), income: false);
      expect(d.reason, isNull);
      expect(d.counterpartyName, 'Hana Girma Alemu');
    });

    test('a page that is not a receipt is unavailable', () {
      expect(
        () => ReceiptReader.parseTelebirr('<html>error</html>', income: false),
        throwsA(isA<ReceiptUnavailable>()),
      );
    });
  });

  group('CBE', () {
    test('expense: description is the reason; receiver name and masked account', () {
      final d = ReceiptReader.parseCbe(cbeJson(), income: false);
      expect(d.reason, 'house rent october');
      expect(d.counterpartyName, 'Dawit Fite Woyessa');
      expect(d.counterpartyAccount, '****6829', reason: 'full account numbers are never kept');
    });

    test('income: the sender is the counterparty', () {
      final d = ReceiptReader.parseCbe(cbeJson(), income: true);
      expect(d.counterpartyName, 'Abebe Kebede Tadesse');
      expect(d.counterpartyAccount, '****4758');
    });

    test('falls back to payment details when there is no description', () {
      expect(ReceiptReader.parseCbe(cbeJson(description: null), income: false).reason, 'house rent octob');
    });
  });

  test('supports only receipts it can read', () {
    expect(ReceiptReader.supports('telebirr', 'DJ50KQ3RTA'), isTrue);
    expect(ReceiptReader.supports('cbe', 'v2-hfHCxHa8Rk2LmPq7Wn'), isTrue);
    expect(ReceiptReader.supports('cbe', 'FT26273XKD4P'), isFalse, reason: 'branch receipts have no reader');
    expect(ReceiptReader.supports('abyssinia', 'FT26274R7KPN81047'), isFalse);
  });

  group('read', () {
    test('calls the right address with CBE headers', () async {
      late http.Request seen;
      final reader = ReceiptReader(
        client: MockClient((req) async {
          seen = req;
          return http.Response.bytes(utf8.encode(jsonEncode(cbeJson())), 200);
        }),
      );
      final d = await reader.read(institution: 'cbe', referenceId: 'v2-abc', income: false);
      expect(seen.url.toString(), 'https://mb.cbe.com.et/api/v1/transactions/public/transaction-detail/v2-abc');
      expect(seen.headers['X-App-ID'], isNotEmpty);
      expect(d.reason, 'house rent october');
    });

    test('404 is unavailable (stop asking); 500 is retryable', () async {
      Future<void> read(int status) =>
          ReceiptReader(client: MockClient((_) async => http.Response('', status)))
              .read(institution: 'telebirr', referenceId: 'DJ50KQ3RTA', income: false);
      await expectLater(read(404), throwsA(isA<ReceiptUnavailable>()));
      await expectLater(read(500), throwsA(isA<http.ClientException>()));
    });
  });
}

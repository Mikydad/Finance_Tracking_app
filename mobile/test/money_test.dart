import 'package:finance_app/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats santim as birr', () {
    expect(formatBirr(250000), '2,500.00');
    expect(formatBirr(10000000), '100,000.00');
    expect(formatBirr(26), '0.26');
    expect(formatBirr(-47700), '-477.00');
  });

  test('parses what users type into santim', () {
    expect(parseBirr('1500'), 150000);
    expect(parseBirr('1,500.5'), 150050);
    expect(parseBirr(' 0.26 '), 26);
    expect(parseBirr('0'), isNull);
    expect(parseBirr('12.345'), isNull);
    expect(parseBirr('abc'), isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/domain/money.dart';
import 'package:pocket_ledger/domain/money_format.dart';

void main() {
  final english = MoneyFormatter(locale: 'en_US');
  final german = MoneyFormatter(locale: 'de_DE');

  group('formatting', () {
    test('renders the amount with the currency symbol', () {
      expect(english.format(const Money(0, Currency.usd)), r'$0.00');
      expect(english.format(const Money(7, Currency.usd)), r'$0.07');
      expect(english.format(const Money(1234, Currency.usd)), r'$12.34');
      expect(english.format(const Money(-809, Currency.usd)), r'-$8.09');
      expect(
        english.format(const Money(123456789, Currency.usd)),
        r'$1,234,567.89',
      );
    });

    test('puts the symbol where the currency wants it', () {
      expect(english.format(const Money(1234, Currency.eur)), '12.34\u00A0€');
      expect(english.format(const Money(1234, Currency.gbp)), '£12.34');
      expect(english.format(const Money(1234, Currency.tryLira)), '₺12.34');
    });

    test('honours a currency with no minor unit', () {
      expect(english.format(const Money(1200, Currency.jpy)), '¥1,200');
      expect(english.format(const Money(-45, Currency.jpy)), '-¥45');
    });

    test('uses the locale separators', () {
      expect(
        german.format(const Money(123456789, Currency.eur)),
        '1.234.567,89\u00A0€',
      );
      expect(german.decimalSeparator, ',');
      expect(german.groupingSeparator, '.');
    });

    test('can force a sign for inflows', () {
      expect(
        english.format(const Money(500, Currency.usd), forceSign: true),
        r'+$5.00',
      );
      expect(
        english.format(const Money(-500, Currency.usd), forceSign: true),
        r'-$5.00',
      );
      expect(
        english.format(const Money(0, Currency.usd), forceSign: true),
        r'$0.00',
      );
    });

    test('can drop the symbol for editing', () {
      expect(english.editable(const Money(1234, Currency.usd)), '12.34');
      expect(english.editable(const Money(-1234, Currency.usd)), '12.34');
      expect(
        english.format(const Money(1234, Currency.usd), showSymbol: false),
        '12.34',
      );
    });

    test('is exact past the range where a double loses digits', () {
      // 2^53 + 1 minor units. Dividing this by 100 into a double and formatting
      // the result would print a different number.
      const beyondDoublePrecision = 9007199254740993;
      expect(
        english.format(const Money(beyondDoublePrecision, Currency.usd)),
        r'$90,071,992,547,409.93',
      );
      expect(
        (beyondDoublePrecision / 100).toStringAsFixed(2),
        isNot('90071992547409.93'),
      );
    });

    test('groups every three digits from the right', () {
      expect(english.format(const Money(100, Currency.usd)), r'$1.00');
      expect(english.format(const Money(100000, Currency.usd)), r'$1,000.00');
      expect(english.format(const Money(1000000, Currency.usd)), r'$10,000.00');
      expect(
        english.format(const Money(10000000, Currency.usd)),
        r'$100,000.00',
      );
      expect(
        english.format(const Money(100000000, Currency.usd)),
        r'$1,000,000.00',
      );
    });
  });

  group('compact formatting', () {
    test('shortens large amounts for chart axes', () {
      expect(english.formatCompact(const Money(50, Currency.usd)), r'$0');
      expect(english.formatCompact(const Money(94900, Currency.usd)), r'$949');
      expect(
        english.formatCompact(const Money(120000, Currency.usd)),
        r'$1.2k',
      );
      expect(
        english.formatCompact(const Money(999900, Currency.usd)),
        r'$9.9k',
      );
      expect(
        english.formatCompact(const Money(1200000, Currency.usd)),
        r'$12k',
      );
      expect(
        english.formatCompact(const Money(340000000, Currency.usd)),
        r'$3.4M',
      );
      expect(
        english.formatCompact(const Money(-120000, Currency.usd)),
        r'-$1.2k',
      );
    });

    test('never rounds a label up beyond the real amount', () {
      // $1,999.99 is not "$2k".
      expect(
        english.formatCompact(const Money(199999, Currency.usd)),
        r'$1.9k',
      );
    });
  });
}

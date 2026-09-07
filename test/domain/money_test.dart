import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/domain/money.dart';

void main() {
  group('parsing', () {
    Money parse(String input, [Currency currency = Currency.usd]) =>
        Money.parse(input, currency);

    test('reads whole and fractional amounts exactly', () {
      expect(parse('0').minorUnits, 0);
      expect(parse('1').minorUnits, 100);
      expect(parse('12.34').minorUnits, 1234);
      expect(parse('0.07').minorUnits, 7);
      expect(parse('.5').minorUnits, 50);
      expect(parse('1.5').minorUnits, 150);
      expect(parse('1.50').minorUnits, 150);
      expect(parse('-8.09').minorUnits, -809);
      expect(parse('+3.10').minorUnits, 310);
    });

    test('never loses a cent to binary floating point', () {
      // Every one of these is a value that `(double.parse(s) * 100).round()`
      // gets right only by accident, and that truncation gets wrong outright.
      const awkward = <String, int>{
        '0.07': 7,
        '1.15': 115,
        '2.67': 267,
        '4.35': 435,
        '8.29': 829,
        '16.08': 1608,
        '70.35': 7035,
        '1.005': -1, // more fraction digits than USD has: rejected
      };

      awkward.forEach((text, expected) {
        final parsed = Money.tryParse(text, Currency.usd);
        if (expected == -1) {
          expect(parsed, isNull, reason: '"$text" should be rejected');
        } else {
          expect(parsed!.minorUnits, expected, reason: text);
        }
      });
    });

    test('accepts grouping separators between digits only', () {
      expect(parse('1,234.56').minorUnits, 123456);
      expect(parse('1,234,567.89').minorUnits, 123456789);
      expect(Money.tryParse('1,,234', Currency.usd), isNull);
      expect(Money.tryParse(',234', Currency.usd), isNull);
      expect(Money.tryParse('1,', Currency.usd), isNull);
    });

    test('honours a locale that swaps the separators', () {
      final parsed = Money.parse(
        '1.234,56',
        Currency.eur,
        decimalSeparator: ',',
        groupingSeparator: '.',
      );
      expect(parsed.minorUnits, 123456);
    });

    test('respects the currency exponent', () {
      expect(Money.parse('1200', Currency.jpy).minorUnits, 1200);
      expect(Money.tryParse('12.5', Currency.jpy), isNull);
    });

    test('rejects anything that is not a number', () {
      for (final input in <String>[
        '',
        '   ',
        'abc',
        '1.2.3',
        '1..2',
        '\$5',
        '5 dollars',
        '1e3',
        '--1',
        '-',
      ]) {
        expect(
          Money.tryParse(input, Currency.usd),
          isNull,
          reason: 'should reject "$input"',
        );
      }
      expect(() => Money.parse('abc', Currency.usd), throwsFormatException);
    });

    test('refuses values that would overflow a 64 bit integer', () {
      // 16 major digits plus 2 cents is 18, the widest value that always fits
      // in a signed 64 bit integer.
      expect(
        Money.tryParse('1' * 16, Currency.usd)!.minorUnits,
        1111111111111111 * 100,
      );
      expect(Money.tryParse('1' * 17, Currency.usd), isNull);
    });
  });

  group('arithmetic', () {
    test('adding tenths stays exact where doubles do not', () {
      const tenCents = Money(10, Currency.usd);
      const twentyCents = Money(20, Currency.usd);

      expect((tenCents + twentyCents).minorUnits, 30);
      // The point of integer money, stated as a test:
      expect(0.1 + 0.2 == 0.3, isFalse);
      expect(tenCents + twentyCents == const Money(30, Currency.usd), isTrue);
    });

    test('a thousand small additions do not drift', () {
      var total = const Money.zero(Currency.usd);
      for (var i = 0; i < 1000; i++) {
        total += const Money(7, Currency.usd);
      }
      expect(total.minorUnits, 7000);

      var asDouble = 0.0;
      for (var i = 0; i < 1000; i++) {
        asDouble += 0.07;
      }
      // The equivalent double sum is off by a fraction of a cent, which is how
      // ledgers end up one cent short.
      expect(asDouble == 70.0, isFalse);
    });

    test('subtraction, negation and absolute value', () {
      const five = Money(500, Currency.usd);
      const three = Money(300, Currency.usd);

      expect((five - three).minorUnits, 200);
      expect((three - five).minorUnits, -200);
      expect((-five).minorUnits, -500);
      expect((three - five).abs, const Money(200, Currency.usd));
      expect((five * 3).minorUnits, 1500);
    });

    test('mixing currencies is an error, not a silent conversion', () {
      const dollars = Money(100, Currency.usd);
      const euros = Money(100, Currency.eur);

      expect(() => dollars + euros, throwsArgumentError);
      expect(() => dollars - euros, throwsArgumentError);
      expect(() => dollars < euros, throwsArgumentError);
      expect(
        () => sumMoney([dollars, euros], Currency.usd),
        throwsArgumentError,
      );
    });

    test('comparison and sorting', () {
      final amounts = [
        const Money(500, Currency.usd),
        const Money(-100, Currency.usd),
        const Money(250, Currency.usd),
      ]..sort();

      expect(amounts.map((m) => m.minorUnits), [-100, 250, 500]);
      expect(
        const Money(100, Currency.usd) < const Money(200, Currency.usd),
        isTrue,
      );
      expect(
        const Money(200, Currency.usd) >= const Money(200, Currency.usd),
        isTrue,
      );
    });

    test('percentages are integer maths, rounded half away from zero', () {
      const limit = Money(60000, Currency.usd);

      expect(const Money(20000, Currency.usd).percentOf(limit), 33);
      expect(const Money(30000, Currency.usd).percentOf(limit), 50);
      expect(const Money(84000, Currency.usd).percentOf(limit), 140);
      // 0.5% rounds up, not to even.
      expect(
        const Money(3, Currency.usd).percentOf(const Money(600, Currency.usd)),
        1,
      );
      expect(
        const Money(1, Currency.usd).percentOf(const Money.zero(Currency.usd)),
        0,
      );
    });

    test('equality includes the currency', () {
      expect(const Money(100, Currency.usd), const Money(100, Currency.usd));
      expect(
        const Money(100, Currency.usd),
        isNot(const Money(100, Currency.eur)),
      );
    });

    test('equal amounts collapse in a set, so hashCode agrees with ==', () {
      // Built at runtime so the analyser cannot fold the two equal amounts
      // into one before the set ever sees them.
      final amounts = <Money>{
        for (final minor in <int>[100, 100]) Money(minor, Currency.usd),
        const Money(100, Currency.eur),
      };

      expect(amounts, hasLength(2));
    });

    test('major units are scaled by the currency exponent', () {
      expect(Money.major(12, Currency.usd).minorUnits, 1200);
      expect(Money.major(12, Currency.jpy).minorUnits, 12);
    });
  });

  group('currencies', () {
    test('are looked up by code and fall back rather than throwing', () {
      expect(Currency.byCode('eur'), Currency.eur);
      expect(Currency.byCode('JPY').decimalDigits, 0);
      expect(Currency.byCode('XXX'), Currency.usd);
      expect(Currency.isSupported('GBP'), isTrue);
      expect(Currency.isSupported('XXX'), isFalse);
    });
  });
}

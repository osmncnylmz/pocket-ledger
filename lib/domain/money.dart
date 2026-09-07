import 'package:meta/meta.dart';

/// A currency, described by everything the app needs to store and render an
/// amount without ever consulting a floating point number.
///
/// [decimalDigits] is the ISO 4217 "minor unit" exponent: 2 for USD (cents),
/// 0 for JPY (there is no sub-yen unit).
@immutable
final class Currency {
  const Currency._(
    this.code,
    this.symbol,
    this.decimalDigits, {
    this.symbolOnLeft = true,
  });

  /// ISO 4217 alphabetic code. This is what is stored in the database.
  final String code;

  /// Display symbol.
  final String symbol;

  /// Number of digits after the decimal separator, i.e. the exponent of the
  /// minor unit. `100 minor units == 1 major unit` when this is 2.
  final int decimalDigits;

  /// Whether the symbol is conventionally written before the digits.
  final bool symbolOnLeft;

  static const usd = Currency._('USD', r'$', 2);
  static const eur = Currency._('EUR', '€', 2, symbolOnLeft: false);
  static const gbp = Currency._('GBP', '£', 2);
  static const tryLira = Currency._('TRY', '₺', 2);
  static const jpy = Currency._('JPY', '¥', 0);

  /// Every currency the app offers. Deliberately short: each entry has to be
  /// verified by hand, and inventing the other 150 would be worse than useless.
  static const supported = <Currency>[usd, eur, gbp, tryLira, jpy];

  /// 10^[decimalDigits], as an exact integer.
  int get minorUnitsPerMajor => _pow10[decimalDigits];

  static const _pow10 = <int>[1, 10, 100, 1000, 10000];

  /// Looks up a currency by ISO code, falling back to [usd] for unknown codes
  /// so that a hand-edited backup file can never brick the app.
  static Currency byCode(String code) {
    final upper = code.toUpperCase();
    for (final currency in supported) {
      if (currency.code == upper) return currency;
    }
    return usd;
  }

  /// Whether [code] names a currency this build knows about.
  static bool isSupported(String code) {
    final upper = code.toUpperCase();
    return supported.any((c) => c.code == upper);
  }

  @override
  bool operator ==(Object other) => other is Currency && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => code;
}

/// An exact monetary amount, stored as a signed count of minor units.
///
/// The entire app — schema, aggregates, parsing, rendering — moves money around
/// as [int]. No `double` is involved at any point, so `0.1 + 0.2` can never
/// become `0.30000000000000004` in a balance.
@immutable
final class Money implements Comparable<Money> {
  const Money(this.minorUnits, this.currency);

  const Money.zero(this.currency) : minorUnits = 0;

  /// Builds an amount from whole major units, e.g. `Money.major(12, usd)` is
  /// `$12.00`.
  Money.major(int majorUnits, this.currency)
    : minorUnits = majorUnits * currency.minorUnitsPerMajor;

  /// Parses user input into an exact amount.
  ///
  /// The whole parse happens on digit *characters*: the integer and fraction
  /// parts are concatenated into one digit string and handed to [int.parse].
  /// Nothing is multiplied by a power of ten in floating point, so
  /// `"0.07"` is always exactly 7 minor units.
  ///
  /// Throws [FormatException] when the input is not a valid amount, has more
  /// fraction digits than the currency allows, or would not fit in an [int].
  factory Money.parse(
    String input,
    Currency currency, {
    String decimalSeparator = '.',
    String groupingSeparator = ',',
  }) {
    final parsed = Money.tryParse(
      input,
      currency,
      decimalSeparator: decimalSeparator,
      groupingSeparator: groupingSeparator,
    );
    if (parsed == null) {
      throw FormatException('Not a valid ${currency.code} amount', input);
    }
    return parsed;
  }

  /// Signed count of minor units (cents, pence, kuruş, ...).
  final int minorUnits;

  final Currency currency;

  bool get isZero => minorUnits == 0;
  bool get isNegative => minorUnits < 0;
  bool get isPositive => minorUnits > 0;

  Money get abs => Money(minorUnits.abs(), currency);

  Money operator -() => Money(-minorUnits, currency);

  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money(minorUnits + other.minorUnits, currency);
  }

  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money(minorUnits - other.minorUnits, currency);
  }

  /// Scales by a whole factor. Kept integral on purpose; there is no
  /// `operator *` taking a `double` because that is where rounding bugs enter.
  Money operator *(int factor) => Money(minorUnits * factor, currency);

  bool operator <(Money other) {
    _assertSameCurrency(other);
    return minorUnits < other.minorUnits;
  }

  bool operator <=(Money other) {
    _assertSameCurrency(other);
    return minorUnits <= other.minorUnits;
  }

  bool operator >(Money other) {
    _assertSameCurrency(other);
    return minorUnits > other.minorUnits;
  }

  bool operator >=(Money other) {
    _assertSameCurrency(other);
    return minorUnits >= other.minorUnits;
  }

  /// This amount as a fraction of [total], in percent, rounded half-up.
  ///
  /// Returns 0 when [total] is zero. Computed with integer arithmetic.
  int percentOf(Money total) {
    _assertSameCurrency(total);
    if (total.minorUnits == 0) return 0;
    final scaled = minorUnits * 200 ~/ total.minorUnits;
    return (scaled + (scaled.isNegative ? -1 : 1)) ~/ 2;
  }

  void _assertSameCurrency(Money other) {
    if (other.currency != currency) {
      throw ArgumentError(
        'Cannot combine ${currency.code} with ${other.currency.code}; '
        'convert explicitly first.',
      );
    }
  }

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minorUnits == minorUnits &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  /// Debug representation. Use `MoneyFormatter` for anything user-visible.
  @override
  String toString() => '${currency.code} $minorUnits';

  /// Like [Money.parse] but returns `null` instead of throwing.
  static Money? tryParse(
    String input,
    Currency currency, {
    String decimalSeparator = '.',
    String groupingSeparator = ',',
  }) {
    var text = input.trim();
    if (text.isEmpty) return null;

    var negative = false;
    if (text.startsWith('-')) {
      negative = true;
      text = text.substring(1).trimLeft();
    } else if (text.startsWith('+')) {
      text = text.substring(1).trimLeft();
    }

    // Grouping separators are cosmetic; strip them, but only between digits so
    // that "1,,000" or a trailing "1," are still rejected.
    if (groupingSeparator.isNotEmpty &&
        groupingSeparator != decimalSeparator &&
        text.contains(groupingSeparator)) {
      final buffer = StringBuffer();
      for (var i = 0; i < text.length; i++) {
        final char = text[i];
        if (char == groupingSeparator) {
          final hasDigitBefore = i > 0 && _isDigit(text[i - 1]);
          final hasDigitAfter = i + 1 < text.length && _isDigit(text[i + 1]);
          if (!hasDigitBefore || !hasDigitAfter) return null;
          continue;
        }
        buffer.write(char);
      }
      text = buffer.toString();
    }

    final separatorIndex = decimalSeparator.isEmpty
        ? -1
        : text.indexOf(decimalSeparator);
    String whole;
    String fraction;
    if (separatorIndex == -1) {
      whole = text;
      fraction = '';
    } else {
      whole = text.substring(0, separatorIndex);
      fraction = text.substring(separatorIndex + decimalSeparator.length);
      // A second separator means the input is malformed.
      if (fraction.contains(decimalSeparator)) return null;
    }

    if (whole.isEmpty && fraction.isEmpty) return null;
    if (!_isAllDigits(whole) || !_isAllDigits(fraction)) return null;
    if (fraction.length > currency.decimalDigits) return null;

    // Pad the fraction so that "1.5" and "1.50" both become 150 minor units.
    final digits =
        (whole.isEmpty ? '0' : whole) +
        fraction.padRight(currency.decimalDigits, '0');

    // 18 digits always fits in a signed 64 bit integer; refuse anything longer
    // rather than silently wrapping around.
    if (digits.length > 18) return null;

    final value = int.tryParse(digits);
    if (value == null) return null;
    return Money(negative ? -value : value, currency);
  }

  static bool _isDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

  static bool _isAllDigits(String text) {
    for (var i = 0; i < text.length; i++) {
      if (!_isDigit(text[i])) return false;
    }
    return true;
  }
}

/// Sums [amounts], which must all share [currency].
Money sumMoney(Iterable<Money> amounts, Currency currency) {
  var total = 0;
  for (final amount in amounts) {
    if (amount.currency != currency) {
      throw ArgumentError('Mixed currencies in sum: ${amount.currency.code}');
    }
    total += amount.minorUnits;
  }
  return Money(total, currency);
}

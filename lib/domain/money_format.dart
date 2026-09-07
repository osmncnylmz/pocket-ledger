import 'package:intl/intl.dart';
import 'package:intl/number_symbols.dart';

import 'money.dart';

/// Renders [Money] without ever converting it to a `double`.
///
/// `intl` supplies the locale's decimal separator, grouping separator and minus
/// sign; the digits themselves are grouped by string slicing. That is the whole
/// trick: an amount of 9,007,199,254,740,993 minor units renders exactly, where
/// dividing by 100 into a `double` would already have lost the last digit.
///
/// Grouping is fixed at three digits, which is correct for every currency the
/// app ships (USD, EUR, GBP, TRY, JPY). Adding an Indian-grouping currency
/// would mean teaching [_group] about lakh/crore.
final class MoneyFormatter {
  MoneyFormatter({String? locale})
    : locale = locale ?? Intl.getCurrentLocale(),
      _symbols = NumberFormat.decimalPattern(locale ?? Intl.getCurrentLocale())
          .symbols;

  final String locale;
  final NumberSymbols _symbols;

  String get decimalSeparator => _symbols.DECIMAL_SEP;
  String get groupingSeparator => _symbols.GROUP_SEP;
  String get minusSign => _symbols.MINUS_SIGN;

  /// Full rendering, e.g. `-$1,234.50` or `1.234,50 €`.
  ///
  /// When [forceSign] is set, positive amounts get an explicit `+`, which is
  /// what the transaction list uses to make inflows obvious.
  String format(Money money, {bool showSymbol = true, bool forceSign = false}) {
    final body = _digits(money);
    final withSymbol = showSymbol ? _applySymbol(body, money.currency) : body;
    return _applySign(withSymbol, money, forceSign: forceSign);
  }

  /// Short rendering for chart axes and dense tiles: `$1.2k`, `$34k`, `$1.1M`.
  ///
  /// Rounds toward zero using integer division, so a compact label never claims
  /// more money than there is.
  String formatCompact(Money money, {bool showSymbol = true}) {
    final currency = money.currency;
    final major = money.minorUnits.abs() ~/ currency.minorUnitsPerMajor;

    String body;
    if (major < 1000) {
      body = _group(major.toString());
    } else {
      const units = <int, String>{1000000000: 'B', 1000000: 'M', 1000: 'k'};
      body = major.toString();
      for (final entry in units.entries) {
        if (major < entry.key) continue;
        final whole = major ~/ entry.key;
        final tenths = (major % entry.key) * 10 ~/ entry.key;
        body = whole < 10 && tenths > 0
            ? '$whole$decimalSeparator$tenths${entry.value}'
            : '$whole${entry.value}';
        break;
      }
    }

    final withSymbol = showSymbol ? _applySymbol(body, currency) : body;
    return _applySign(withSymbol, money, forceSign: false);
  }

  /// The digits only: no sign, no currency symbol. This is what the amount
  /// input field shows while editing.
  String editable(Money money) => _digits(money);

  String _digits(Money money) {
    final currency = money.currency;
    final magnitude = money.minorUnits.abs().toString().padLeft(
      currency.decimalDigits + 1,
      '0',
    );
    final splitAt = magnitude.length - currency.decimalDigits;
    final whole = _group(magnitude.substring(0, splitAt));
    if (currency.decimalDigits == 0) return whole;
    return '$whole$decimalSeparator${magnitude.substring(splitAt)}';
  }

  /// Non-breaking space between the digits and a trailing symbol, so
  /// `1.234,56 €` never wraps with the euro sign alone on the next line.
  static const _nbsp = '\u00A0';

  String _applySymbol(String body, Currency currency) => currency.symbolOnLeft
      ? '${currency.symbol}$body'
      : '$body$_nbsp${currency.symbol}';

  String _applySign(String text, Money money, {required bool forceSign}) {
    if (money.isNegative) return '$minusSign$text';
    if (forceSign && money.isPositive) return '${_symbols.PLUS_SIGN}$text';
    return text;
  }

  /// Groups from the right, three at a time.
  String _group(String digits) {
    if (digits.length <= 3) return digits;
    final buffer = StringBuffer();
    final firstGroup = digits.length % 3 == 0 ? 3 : digits.length % 3;
    buffer.write(digits.substring(0, firstGroup));
    for (var i = firstGroup; i < digits.length; i += 3) {
      buffer
        ..write(groupingSeparator)
        ..write(digits.substring(i, i + 3));
    }
    return buffer.toString();
  }
}

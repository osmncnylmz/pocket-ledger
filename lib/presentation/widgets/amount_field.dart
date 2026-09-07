import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/money.dart';
import '../theme.dart';

/// Rejects any keystroke that would leave the field holding something that is
/// not an exact amount in [currency].
///
/// The field therefore cannot reach a state that needs rounding to interpret:
/// there is no `double.parse` anywhere in the path from keyboard to database.
/// A lone trailing decimal separator is allowed through as a transient state
/// so that typing `1`, `.`, `5` works.
class MoneyInputFormatter extends TextInputFormatter {
  MoneyInputFormatter({required this.currency, required this.decimalSeparator});

  final Currency currency;
  final String decimalSeparator;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    if (_isAcceptable(text)) return newValue;
    return oldValue;
  }

  bool _isAcceptable(String text) {
    if (Money.tryParse(
          text,
          currency,
          decimalSeparator: decimalSeparator,
          groupingSeparator: '',
        ) !=
        null) {
      return true;
    }

    // "12." on the way to "12.5".
    if (currency.decimalDigits > 0 &&
        text.endsWith(decimalSeparator) &&
        decimalSeparator.allMatches(text).length == 1) {
      final withoutSeparator = text.substring(
        0,
        text.length - decimalSeparator.length,
      );
      return withoutSeparator.isEmpty ||
          Money.tryParse(
                withoutSeparator,
                currency,
                decimalSeparator: decimalSeparator,
                groupingSeparator: '',
              ) !=
              null;
    }

    return false;
  }
}

/// The amount input used by the transaction and budget editors.
///
/// Shows the currency symbol as a prefix, uses a numeric keyboard, and hands
/// back a [Money] — never a string or a `double`.
class AmountField extends StatelessWidget {
  const AmountField({
    required this.controller,
    required this.currency,
    required this.decimalSeparator,
    super.key,
    this.label = 'Amount',
    this.autofocus = false,
    this.onSubmitted,
    this.errorText,
  });

  final TextEditingController controller;
  final Currency currency;
  final String decimalSeparator;
  final String label;
  final bool autofocus;
  final VoidCallback? onSubmitted;
  final String? errorText;

  /// The current contents as money, or `null` while the field is empty or
  /// mid-edit.
  static Money? read(
    TextEditingController controller,
    Currency currency,
    String decimalSeparator,
  ) {
    return Money.tryParse(
      controller.text,
      currency,
      decimalSeparator: decimalSeparator,
      groupingSeparator: '',
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.numberWithOptions(
        decimal: currency.decimalDigits > 0,
      ),
      textInputAction: TextInputAction.done,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      inputFormatters: [
        MoneyInputFormatter(
          currency: currency,
          decimalSeparator: decimalSeparator,
        ),
      ],
      style: context.texts.headlineSmall,
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: Insets.lg, right: Insets.sm),
          child: Text(
            currency.symbol,
            style: context.texts.headlineSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(),
      ),
    );
  }
}

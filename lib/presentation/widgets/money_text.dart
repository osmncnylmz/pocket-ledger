import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/money.dart';
import '../providers.dart';
import '../theme.dart';

/// Renders a [Money] with the app's formatter and, optionally, the
/// income/expense colour.
///
/// Kept as a widget rather than a helper function so that every amount in the
/// app picks up the same tabular figures and the same sign convention.
class MoneyText extends ConsumerWidget {
  const MoneyText(
    this.amount, {
    super.key,
    this.style,
    this.colorBySign = false,
    this.forceSign = false,
    this.compact = false,
    this.showSymbol = true,
    this.semanticPrefix,
  });

  final Money amount;
  final TextStyle? style;

  /// Green for inflows, red for outflows. Off by default: most amounts read
  /// better in the normal text colour, with colour reserved for the places it
  /// carries information.
  final bool colorBySign;

  final bool forceSign;
  final bool compact;
  final bool showSymbol;

  /// Prefix for the screen reader, e.g. "Balance".
  final String? semanticPrefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formatter = ref.watch(moneyFormatterProvider);
    final text = compact
        ? formatter.formatCompact(amount, showSymbol: showSymbol)
        : formatter.format(
            amount,
            showSymbol: showSymbol,
            forceSign: forceSign,
          );

    Color? color;
    if (colorBySign && !amount.isZero) {
      color = amount.isNegative
          ? context.ledgerColors.expense
          : context.ledgerColors.income;
    }

    final full = formatter.format(amount, forceSign: forceSign);
    return Semantics(
      label: semanticPrefix == null ? full : '$semanticPrefix $full',
      excludeSemantics: true,
      child: Text(
        text,
        style: (style ?? DefaultTextStyle.of(context).style).copyWith(
          color: color,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

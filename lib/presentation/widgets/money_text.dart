import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/money.dart';
import '../providers.dart';
import '../theme.dart';

/// Tabular figures and the sign convention, in one place.
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

  /// Green for inflows, red for outflows. Off by default — colour is worth
  /// more where it is scarce.
  final bool colorBySign;

  final bool forceSign;
  final bool compact;
  final bool showSymbol;

  /// Read out before the amount, e.g. "Balance".
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

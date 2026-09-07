import 'package:flutter/material.dart';

import '../../domain/services/budget_evaluator.dart';
import '../category_icons.dart';
import '../theme.dart';
import 'money_text.dart';

/// A budget with an animated progress bar and a marker showing where an evenly
/// paced spender would be today.
class BudgetTile extends StatelessWidget {
  const BudgetTile({
    required this.progress,
    super.key,
    this.onTap,
    this.showPaceMarker = true,
  });

  final BudgetProgress progress;
  final VoidCallback? onTap;
  final bool showPaceMarker;

  Color _barColor(BuildContext context) => switch (progress.health) {
    BudgetHealth.onTrack => context.ledgerColors.income,
    BudgetHealth.aheadOfPace => context.ledgerColors.warning,
    BudgetHealth.overBudget => context.ledgerColors.expense,
  };

  String get _status => switch (progress.health) {
    BudgetHealth.onTrack => 'On track',
    BudgetHealth.aheadOfPace => 'Ahead of pace',
    BudgetHealth.overBudget => 'Over budget',
  };

  @override
  Widget build(BuildContext context) {
    final barColor = _barColor(context);
    final categoryColor = Color(progress.category.colorValue);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  categoryIconFor(progress.category.iconKey),
                  size: 18,
                  color: categoryColor,
                ),
                const SizedBox(width: Insets.sm),
                Expanded(
                  child: Text(
                    progress.category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '${progress.percentUsed}%',
                  style: context.texts.labelLarge?.copyWith(color: barColor),
                ),
              ],
            ),
            const SizedBox(height: Insets.sm),
            _ProgressBar(
              fraction: progress.fractionUsed,
              paceFraction: showPaceMarker ? _paceFraction : null,
              color: barColor,
            ),
            const SizedBox(height: Insets.sm),
            Row(
              children: [
                // The status keeps its natural width and the amounts give way
                // to it, so a long category currency or a large limit narrows
                // the figures rather than pushing the status off the tile.
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: MoneyText(
                          progress.spent,
                          style: context.texts.bodySmall,
                        ),
                      ),
                      Text(
                        ' of ',
                        style: context.texts.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                      Flexible(
                        child: MoneyText(
                          progress.limit,
                          style: context.texts.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Insets.sm),
                Text(
                  _status,
                  style: context.texts.bodySmall?.copyWith(color: barColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double? get _paceFraction {
    final limit = progress.limit.minorUnits;
    if (limit <= 0) return null;
    final fraction = progress.expectedSpendAtPace.minorUnits / limit;
    if (fraction <= 0 || fraction >= 1) return null;
    return fraction;
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.fraction,
    required this.color,
    this.paceFraction,
  });

  final double fraction;
  final double? paceFraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: 10,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: fraction),
                duration: Motion.of(context, Motion.chart),
                curve: Motion.curve,
                builder: (context, value, _) => Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                    width: width * value,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ),
              if (paceFraction != null)
                Positioned(
                  left: (width * paceFraction!).clamp(0, width - 2),
                  top: 0,
                  bottom: 0,
                  child: Tooltip(
                    message: 'Even pace for today',
                    child: Container(
                      width: 2,
                      color: context.colors.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

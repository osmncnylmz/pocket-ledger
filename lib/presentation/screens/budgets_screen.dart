import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/enums.dart';
import '../../domain/money.dart';
import '../../domain/services/budget_evaluator.dart';
import '../providers.dart';
import '../sheets/budget_editor_sheet.dart';
import '../theme.dart';
import '../widgets/budget_tile.dart';
import '../widgets/empty_state.dart';
import '../widgets/money_text.dart';
import '../widgets/section_card.dart';

/// Every limit the user has set, grouped by the window it applies to.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetProgressProvider);
    final month = ref.watch(selectedMonthProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgets'),
        actions: [
          IconButton(
            tooltip: 'New budget',
            onPressed: () => showBudgetEditor(context),
            icon: const Icon(Icons.add),
          ),
          const SizedBox(width: Insets.sm),
        ],
      ),
      body: switch (budgets) {
        AsyncError(:final error) => Center(child: Text('$error')),
        AsyncData(value: final all) when all.isEmpty => EmptyState(
          icon: Icons.savings_outlined,
          title: 'No budgets yet',
          message:
              'Set a limit on a category and this screen tracks it against the '
              'calendar.',
          action: FilledButton.icon(
            onPressed: () => showBudgetEditor(context),
            icon: const Icon(Icons.add),
            label: const Text('Set a budget'),
          ),
        ),
        AsyncData(value: final all) => ListView(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            Insets.md,
            Insets.lg,
            Insets.xxl * 2,
          ),
          children: [
            for (final period in BudgetPeriod.values)
              if (all.any((p) => p.budget.period == period))
                Padding(
                  padding: const EdgeInsets.only(bottom: Insets.md),
                  child: _PeriodSection(
                    period: period,
                    progress: all
                        .where((p) => p.budget.period == period)
                        .toList(),
                    month: month,
                  ),
                ),
          ],
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _PeriodSection extends ConsumerWidget {
  const _PeriodSection({
    required this.period,
    required this.progress,
    required this.month,
  });

  final BudgetPeriod period;
  final List<BudgetProgress> progress;
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(activeCurrencyProvider);
    final spent = progress
        .map((p) => p.spent)
        .fold(Money.zero(currency), (a, b) => a + b);
    final limit = progress
        .map((p) => p.limit)
        .fold(Money.zero(currency), (a, b) => a + b);

    final window = progress.first.window;
    final subtitle = switch (period) {
      BudgetPeriod.monthly => DateFormat.yMMMM().format(window.start),
      BudgetPeriod.weekly =>
        'Week of ${DateFormat.MMMd().format(window.start)}',
      BudgetPeriod.yearly => DateFormat.y().format(window.start),
    };

    return SectionCard(
      title: period.label,
      subtitle: subtitle,
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.lg,
        Insets.lg,
        Insets.sm,
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          MoneyText(spent, style: context.texts.titleMedium),
          MoneyText(
            limit,
            style: context.texts.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
      child: Column(
        children: [
          for (final item in progress)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Insets.xs),
              child: BudgetTile(
                progress: item,
                onTap: () => showBudgetEditor(context, existing: item),
              ),
            ),
        ],
      ),
    );
  }
}

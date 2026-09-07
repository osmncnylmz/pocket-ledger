import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities.dart';
import '../../domain/money.dart';
import '../../domain/services/budget_evaluator.dart';
import '../category_icons.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/budget_tile.dart';
import '../widgets/donut_chart.dart';
import '../widgets/empty_state.dart';
import '../widgets/money_text.dart';
import '../widgets/section_card.dart';
import '../widgets/trend_chart.dart';

/// The dashboard: where the money is, where it went this month, and whether
/// that is a problem.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key, this.onSeeAllBudgets});

  final VoidCallback? onSeeAllBudgets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('Pocket Ledger'),
            actions: [
              _MonthStepper(month: month),
              const SizedBox(width: Insets.sm),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              0,
              Insets.lg,
              Insets.xxl * 2,
            ),
            sliver: SliverList.list(
              children: const [
                _BalanceCard(),
                SizedBox(height: Insets.md),
                _MonthSummaryCard(),
                SizedBox(height: Insets.md),
                _SpendByCategoryCard(),
                SizedBox(height: Insets.md),
                _TrendCard(),
                SizedBox(height: Insets.md),
                _BudgetsPreviewCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthStepper extends ConsumerWidget {
  const _MonthStepper({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider);
    final isCurrentMonth = month.year == now.year && month.month == now.month;
    final controller = ref.read(selectedMonthProvider.notifier);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: controller.previous,
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous month',
        ),
        AnimatedSwitcher(
          duration: Motion.of(context, Motion.quick),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SizeTransition(
              axis: Axis.horizontal,
              sizeFactor: animation,
              child: child,
            ),
          ),
          child: Text(
            DateFormat.yMMM().format(month),
            key: ValueKey(month),
            style: context.texts.titleSmall,
          ),
        ),
        IconButton(
          onPressed: isCurrentMonth ? null : controller.next,
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next month',
        ),
      ],
    );
  }
}

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(accountBalancesProvider);
    final totals = ref.watch(totalsByCurrencyProvider);
    final currency = ref.watch(activeCurrencyProvider);

    return SectionCard(
      title: 'Balance',
      subtitle: 'Across your accounts',
      child: switch (balances) {
        AsyncError(:final error) => SectionError(message: '$error'),
        AsyncData(value: final accounts) when accounts.isEmpty =>
          const EmptyState(
            icon: Icons.account_balance_wallet_outlined,
            title: 'No accounts yet',
            message: 'Add an account in Settings to start tracking a balance.',
            compact: true,
          ),
        AsyncData(value: final accounts) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MoneyText(
              totals.value?[currency] ?? Money.zero(currency),
              style: context.texts.displaySmall,
              semanticPrefix: 'Total balance',
            ),
            for (final other
                in (totals.value ?? const <Currency, Money>{}).entries.where(
                  (entry) => entry.key != currency,
                ))
              Padding(
                padding: const EdgeInsets.only(top: Insets.xs),
                child: MoneyText(
                  other.value,
                  style: context.texts.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: Insets.lg),
            for (final balance in accounts) _AccountRow(balance: balance),
          ],
        ),
        _ => const SectionLoading(height: 120),
      },
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.balance});

  final AccountBalance balance;

  @override
  Widget build(BuildContext context) {
    final color = Color(balance.account.colorValue);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.xs),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              accountIcons[balance.account.kind.name] ??
                  Icons.account_balance_outlined,
              size: 16,
              color: color,
            ),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Text(
              balance.account.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodyMedium,
            ),
          ),
          MoneyText(
            balance.balance,
            style: context.texts.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            colorBySign:
                balance.balance.isNegative && !balance.account.kind.isLiability,
          ),
        ],
      ),
    );
  }
}

class _MonthSummaryCard extends ConsumerWidget {
  const _MonthSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final trend = ref.watch(trendProvider);
    final budgets = ref.watch(monthlyBudgetProgressProvider);
    final currency = ref.watch(activeCurrencyProvider);

    final totals = trend.value?.lastOrNull;
    final income = totals?.income ?? Money.zero(currency);
    final expense = totals?.expense ?? Money.zero(currency);

    final limit = budgets.value == null || budgets.value!.isEmpty
        ? null
        : budgets.value!.map((p) => p.limit).reduce((a, b) => a + b);
    final budgeted = budgets.value == null || budgets.value!.isEmpty
        ? null
        : budgets.value!.map((p) => p.spent).reduce((a, b) => a + b);

    return SectionCard(
      title: DateFormat.yMMMM().format(month),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'Spent',
                  amount: expense,
                  color: context.ledgerColors.expense,
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'Received',
                  amount: income,
                  color: context.ledgerColors.income,
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'Net',
                  amount: income - expense,
                  color: context.colors.onSurface,
                ),
              ),
            ],
          ),
          if (limit != null && budgeted != null && limit.isPositive) ...[
            const SizedBox(height: Insets.lg),
            _BudgetSummaryBar(spent: budgeted, limit: limit),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.amount, required this.color});

  final String label;
  final Money amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.texts.labelMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Insets.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: MoneyText(
            amount,
            semanticPrefix: label,
            style: context.texts.titleMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _BudgetSummaryBar extends StatelessWidget {
  const _BudgetSummaryBar({required this.spent, required this.limit});

  final Money spent;
  final Money limit;

  @override
  Widget build(BuildContext context) {
    final fraction = (spent.minorUnits / limit.minorUnits).clamp(0.0, 1.0);
    final over = spent >= limit;
    final color = over ? context.ledgerColors.expense : context.colors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Budgeted categories',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.labelMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: Insets.sm),
            Flexible(child: MoneyText(spent, style: context.texts.labelMedium)),
            Text(
              ' / ',
              style: context.texts.labelMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            Flexible(
              child: MoneyText(
                limit,
                style: context.texts.labelMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.sm),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: fraction),
          duration: Motion.of(context, Motion.chart),
          curve: Motion.curve,
          builder: (context, value, _) => ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 10,
              backgroundColor: context.colors.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      ],
    );
  }
}

class _SpendByCategoryCard extends ConsumerStatefulWidget {
  const _SpendByCategoryCard();

  @override
  ConsumerState<_SpendByCategoryCard> createState() =>
      _SpendByCategoryCardState();
}

class _SpendByCategoryCardState extends ConsumerState<_SpendByCategoryCard> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final spend = ref.watch(monthlySpendProvider);
    final currency = ref.watch(activeCurrencyProvider);

    return SectionCard(
      title: 'Where it went',
      child: switch (spend) {
        AsyncError(:final error) => SectionError(message: '$error'),
        AsyncData(value: final categories) when categories.isEmpty =>
          const EmptyState(
            icon: Icons.pie_chart_outline,
            title: 'Nothing spent this month',
            message:
                'Expenses you record will be broken down by category here.',
            compact: true,
          ),
        AsyncData(value: final categories) => _buildChart(categories, currency),
        _ => const SectionLoading(height: 200),
      },
    );
  }

  Widget _buildChart(List<CategorySpend> categories, Currency currency) {
    final shown = categories.take(6).toList();
    final rest = categories.skip(6).toList();
    final slices = <DonutSlice>[
      for (var i = 0; i < shown.length; i++)
        DonutSlice(
          label: shown[i].category.name,
          value: shown[i].total.minorUnits,
          color: _colorFor(shown[i], i),
        ),
      if (rest.isNotEmpty)
        DonutSlice(
          label: 'Other',
          value: rest.fold(0, (sum, s) => sum + s.total.minorUnits),
          color: context.colors.outline,
        ),
    ];

    final total = Money(
      slices.fold(0, (sum, slice) => sum + slice.value),
      currency,
    );
    final selected = _selected != null && _selected! < slices.length
        ? slices[_selected!]
        : null;

    return Column(
      children: [
        SizedBox(
          height: 190,
          child: DonutChart(
            slices: slices,
            selectedIndex: _selected,
            onSliceTapped: (index) =>
                setState(() => _selected = index == _selected ? null : index),
            centre: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  selected?.label ?? 'Total',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.labelMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                MoneyText(
                  selected == null ? total : Money(selected.value, currency),
                  style: context.texts.titleLarge,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Insets.lg),
        Wrap(
          spacing: Insets.md,
          runSpacing: Insets.sm,
          children: [
            for (var i = 0; i < slices.length; i++)
              _LegendChip(
                slice: slices[i],
                selected: _selected == i,
                onTap: () =>
                    setState(() => _selected = _selected == i ? null : i),
              ),
          ],
        ),
      ],
    );
  }

  Color _colorFor(CategorySpend spend, int index) {
    final stored = spend.category.colorValue;
    if (stored != 0) return Color(stored);
    return categoryFallbackPalette[index % categoryFallbackPalette.length];
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.slice,
    required this.selected,
    required this.onTap,
  });

  final DonutSlice slice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: slice.color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: Insets.sm),
            Text(
              slice.label,
              style: context.texts.bodySmall?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected
                    ? context.colors.onSurface
                    : context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendCard extends ConsumerStatefulWidget {
  const _TrendCard();

  @override
  ConsumerState<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends ConsumerState<_TrendCard> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final trend = ref.watch(trendProvider);
    final formatter = ref.watch(moneyFormatterProvider);
    final currency = ref.watch(activeCurrencyProvider);

    return SectionCard(
      title: 'Six month trend',
      subtitle: 'Spending against income',
      child: switch (trend) {
        AsyncError(:final error) => SectionError(message: '$error'),
        AsyncData(value: final months) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TrendLegend(
              months: months,
              selectedIndex: _selected,
              currency: currency,
            ),
            const SizedBox(height: Insets.sm),
            TrendChart(
              points: [
                for (final month in months)
                  TrendPoint(
                    label: DateFormat.MMM().format(month.month),
                    income: month.income.minorUnits,
                    expense: month.expense.minorUnits,
                  ),
              ],
              selectedIndex: _selected,
              onSelected: (index) => setState(() => _selected = index),
              formatValue: (minor) =>
                  formatter.formatCompact(Money(minor, currency)),
            ),
          ],
        ),
        _ => const SectionLoading(height: 190),
      },
    );
  }
}

class _TrendLegend extends StatelessWidget {
  const _TrendLegend({
    required this.months,
    required this.selectedIndex,
    required this.currency,
  });

  final List<MonthlyTotals> months;
  final int? selectedIndex;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    final index = selectedIndex ?? months.length - 1;
    if (index < 0 || index >= months.length) return const SizedBox.shrink();
    final month = months[index];

    return Row(
      children: [
        Expanded(
          child: Text(
            DateFormat.yMMM().format(month.month),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.labelLarge?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
        _Dot(color: context.ledgerColors.expense),
        const SizedBox(width: Insets.xs),
        MoneyText(
          month.expense,
          style: context.texts.labelLarge,
          compact: true,
        ),
        const SizedBox(width: Insets.md),
        _Dot(color: context.ledgerColors.income),
        const SizedBox(width: Insets.xs),
        MoneyText(month.income, style: context.texts.labelLarge, compact: true),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _BudgetsPreviewCard extends ConsumerWidget {
  const _BudgetsPreviewCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(monthlyBudgetProgressProvider);

    return SectionCard(
      title: 'Budgets',
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.lg,
        Insets.lg,
        Insets.sm,
      ),
      child: switch (budgets) {
        AsyncError(:final error) => SectionError(message: '$error'),
        AsyncData(value: final all) when all.isEmpty => const EmptyState(
          icon: Icons.savings_outlined,
          title: 'No budgets set',
          message:
              'Set a monthly limit on a category to see how you are '
              'tracking against it.',
          compact: true,
        ),
        AsyncData(value: final all) => Column(
          children: [
            for (final progress in _mostUrgent(all))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Insets.xs),
                child: BudgetTile(progress: progress),
              ),
          ],
        ),
        _ => const SectionLoading(height: 120),
      },
    );
  }

  /// The three budgets most worth looking at: the ones furthest along.
  static List<BudgetProgress> _mostUrgent(List<BudgetProgress> all) {
    final sorted = [...all]
      ..sort((a, b) => b.percentUsed.compareTo(a.percentUsed));
    return sorted.take(3).toList();
  }
}
